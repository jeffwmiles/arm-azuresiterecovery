<#
 .Synopsis
  This will attach a pre-existing Public IP address to the RDP server.

 .Description
 This allows the Privileged Access Management appliance to connect to the RDP jump host securely.
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
# End Automation Variables
## ------------

# Define Resource Group that the Public IP is expected to reside in (created from Terraform)
$PublicIPResourceGroup = "$($prefix)-dr-srv-rg"
$rdpResourceGroupName = "$($prefix)-dr-mgmt" # Resource Group that RDP VM will be built in by ASR

# Get RDP VM
Try {
    # During a test, there may be more than 1 VM with this name, so we need the correct Resource Group for Disaster Recovery
    $VMs = Get-AzVm -Name "$($prefix)-rdp1*" -ResourceGroupName $rdpResourceGroupName # use star wildcard as recovery plan appends 'test' to the VM name
    Write-Output ("Found the following VMs: `n " + $VMs.Name)
}
Catch {
    $ErrorMessage = 'Failed to find any VMs in the Resource Group.'
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
        -ErrorAction Stop
}
# Get Public IP (previously created from Terraform)
Try {
    $pip = Get-AzPublicIpAddress -Name "$($prefix)-drrdp-ip" -ResourceGroupName $PublicIPResourceGroup
    Write-Output ("Found the following IPaddress: `n " + $pip.Name)
}
Catch {
    $ErrorMessage = 'Failed to find any Public IP address in the Resource Group.'
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
        -ErrorAction Stop
}

Try {
    foreach ($VM in $VMs) {
        $vmNIC = Get-AzResource -ResourceId $VM.NetworkProfile.NetworkInterfaces.Id
        $NIC = Get-AzNetworkInterface -Name $vmNIC.Name -ResourceGroupName $vmNIC.ResourceGroupName
        $NIC.IpConfigurations[0].PublicIpAddress = $pip
        Set-AzNetworkInterface -NetworkInterface $NIC
        Write-Output ("Added public IP address to the following VM: " + $VM.Name)
    }
    Write-Output ("Operation completed on the following VM(s): `n" + $VMs.Name)
}
Catch {
    $ErrorMessage = 'Failed to add public IP address to the VM.'
    $ErrorMessage += " `n"
    $ErrorMessage += 'Error: '
    $ErrorMessage += $_
    Write-Error -Message $ErrorMessage `
        -ErrorAction Stop
}