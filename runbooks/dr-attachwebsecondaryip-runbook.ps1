<#
 .Synopsis
 Apply secondary IP addresses to Web Servers for IIS bindings to function

 .Description
 ASR does not replicate secondary NICs or IP addresses
 Since IIS is bound to them, we need to re-add them, based on a stored Automation variable, and a standard numbering scheme.
 The config that is added should match what was originally deployed by Terraform

 Contents of this script strongly assume static numbering scheme, and may need to be modified.

#>

    param (
        [Object]$RecoveryPlanContext
    )
    Write-Output $RecoveryPlanContext

    Try {
        "Logging in to Azure..."
        $Conn = Get-AutomationConnection -Name AzureRunAsConnection
        Add-AzAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
        "Selecting Azure subscription..."
        Select-AzSubscription -SubscriptionId $Conn.SubscriptionID -TenantId $Conn.tenantid
    }
    Catch {
        $ErrorMessage = 'Login to Azure subscription failed.'
        $ErrorMessage += " `n"
        $ErrorMessage += 'Error: '
        $ErrorMessage += $_
        Write-Error -Message $ErrorMessage `
            -ErrorAction Stop
    }
    ## ------------
    ## Automation Variables
    $prefix = Get-AutomationVariable -Name 'prefix'
    $first3octets = Get-AutomationVariable -Name 'First3Octets'
    # End Automation Variables
    ## ------------

# Define the VMs you wish to have IP addresses added to, and their IP config
$VMsToModify =
@(
    # use star wildcard in vmname as recovery plan appends 'test' to the VM name
    # use star in resourcegroupname to avoid passing in the builddate
    [pscustomobject]@{  vmname = "$($prefix)-web1*"; primaryip = "$first3octets.30"; ipconfig2 = "$first3octets.40"; subnet = "$($prefix)-web-sub"; resourcegroupname = "$($prefix)-dr-web" },
    [pscustomobject]@{  vmname = "$($prefix)-web2*"; primaryip = "$first3octets.50"; ipconfig2 = "$first3octets.60"; subnet = "$($prefix)-web-sub"; resourcegroupname = "$($prefix)-dr-web" }
)

    ## ------------
    ## Static Variables - won't change for each implementation of this runbook
    $vnetName = "$prefix-vnet" # statically set based on naming convention
    $drVnetResourceGroupName = "$($prefix)-dr-srv-rg"
    ## End Static Variables
    ## ------------

    # Must specify ResourceGroupName otherwise we get 2 VNETs (source and DR)
    $vnet = get-azvirtualnetwork -Name $vnetName -ResourceGroupName $drVnetResourceGroupName

    foreach ($object in $VMsToModify) {
        # Define the ipconfig2 values from the $object
        $Subnet = Get-AzVirtualNetworkSubnetConfig -Name $object.subnet -VirtualNetwork $vnet

        # Begin to add the ipconfig in Azure for the VM
        $VM = Get-AzVm -Name $object.vmname -ResourceGroupName $object.resourcegroupname
        $vmNIC = Get-AzResource -ResourceId $VM.NetworkProfile.NetworkInterfaces.Id
        $NIC = Get-AzNetworkInterface -Name $vmNIC.Name -ResourceGroupName $vmNIC.ResourceGroupName

        # Add ipconfig2
        try {
            Add-AzNetworkInterfaceIpConfig -Name "ipconfig2" -NetworkInterface $NIC -Subnet $Subnet -PrivateIpAddress $object.ipconfig2 -PrivateIpAddressVersion "IPv4"
            Write-Output ("Added ipconfig2 to the following NIC: " + $NIC.Name)
        }
        Catch {
            $ErrorMessageInt = 'Failed to add ipconfig2 to the NIC.'
            $ErrorMessageInt += " `n"
            $ErrorMessageInt += 'Error: '
            $ErrorMessageInt += $_
            Write-Error -Message $ErrorMessageInt `
                -ErrorAction Stop
        }
        # Apply the new ip configurations in Azure
        try {
            Set-AzNetworkInterface -NetworkInterface $NIC
            Write-Output ("Set updated properties on: " + $NIC.Name)
        }
        Catch {
            $ErrorMessageInt = 'Failed to update NIC.'
            $ErrorMessageInt += " `n"
            $ErrorMessageInt += 'Error: '
            $ErrorMessageInt += $_
            Write-Error -Message $ErrorMessageInt `
                -ErrorAction Stop
        }

        # Invoke a command inside the VM, to run DSC which will apply the static IP settings
        # static IP inside the VM needs to match what is configured in the Azure Portal, since more than 1 ipconfig exists.
        $commandpath = ".\SetStaticIPAddresses.ps1"
        $remoteCommand =
        @'
        param (
        [string]$First3Octets,
        [string]$SubnetMask = "27",
        [string]$PrimaryIP,
        [string]$IPsToAddString
        )
        # split function
        $IPsToAdd = $IPsToAddString.Split(',')
        $AppsIp = $IPsToAdd[0]

        Configuration applystaticip {
        Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
        Import-DscResource -ModuleName 'NetworkingDSC' -ModuleVersion "7.4.0.0"
        Node 'localhost'
        {
            $InterfaceAlias = "Ethernet"
            $DNSServer1 = "$($First3Octets).10"
            $DNSServer2 = "$($First3Octets).11"
            ## Calc Default Gateway
            $calcip = [ipaddress]$PrimaryIP
            $CIDR_Bits = ('1' * $SubnetMask).PadRight(32, "0")
            # Split into groups of 8 bits, convert to Ints, join up into a string
            $Octets = $CIDR_Bits -split '(.{8})' -ne ''
            $mask = ($Octets | ForEach-Object -Process {[Convert]::ToInt32($_, 2) }) -join '.'
            $netid = ([ipaddress]($calcip.Address -band ([ipaddress]$mask).Address)).IPAddressToString
            $gatewayOctets = $netid.Split('.')
            $gatewayOctets[-1] = [decimal]$gatewayOctets[-1] + 1
            $defaultGateway = $gatewayOctets -join '.'
            ## End Calc default gateway

            NetIPInterface DisabledDhcpClient
            {
                Dhcp          = 'Disabled'
                InterfaceAlias = "$InterfaceAlias" # ASR deploys new NIC as Ethernet
                AddressFamily  = 'IPv4'
            }
            IPAddress NewIPv4AddressApps {
                #Multiple IPs can be comma delimited like this
                IPAddress      = "$($PrimaryIP)/$($SubnetMask)", "$($AppsIP)/$($SubnetMask)"
                InterfaceAlias = "$InterfaceAlias"
                AddressFamily  = 'IPV4'
            }
            IPAddressOption SetSkipAsSourceApps { # Skip as source on secondary IP address, in order to prevent DNS registration of this second IP
                IPAddress    = "$AppsIP"
                SkipAsSource = $true
                DependsOn    = "[IPAddress]NewIPv4AddressApps"
            }
            DefaultGatewayAddress SetDefaultGateway {
                Address        = "$DefaultGateway"
                InterfaceAlias = "$InterfaceAlias"
                AddressFamily  = 'IPv4'
                DependsOn      = "[IPAddress]NewIPv4AddressApps", "[NetIPInterface]DisabledDhcpClient"
            }
            DnsServerAddress DnsServerAddress {
                Address        = "$DNSServer1", "$DNSServer2"
                InterfaceAlias = "$InterfaceAlias"
                AddressFamily  = 'IPv4'
                DependsOn      = "[NetIPInterface]DisabledDhcpClient"
            }
            }
         }
        }
        cd c:\temp\
        applystaticip
        Start-DscConfiguration .\applystaticip -Wait -Verbose -force
'@
        # Save the command to a local file
        Write-Output ("Write VMRunCommand locally.")
        Set-Content -Path $commandpath -Value $remoteCommand
        # Invoke the command on the VM, using the local file
        $runcmdparameters = @{ # otherwise run it without the param for ipconfig3
            "First3Octets"   = $first3octets;
            "PrimaryIP"      = $object.primaryip;
            "IPsToAddString" = "$($object.ipconfig2)";
        }
        Invoke-AzVMRunCommand -Name $VM.Name -ResourceGroupName $VM.resourcegroupname -CommandId 'RunPowerShellScript' -ScriptPath $commandpath -Parameter $runcmdparameters
        Write-Output ("Invoked the VMRunCommand.")
        # Clean-up the local file
        Remove-Item $commandpath
    }