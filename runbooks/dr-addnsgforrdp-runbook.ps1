<#
 .Synopsis
  Add NSG rule for each of the DR subnets for port 3389

 .Description
 This allows the RDP jump host to natively jump into each one, during a Test Failover only.
 Uses Automation Variables that are expected to be present
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

## ------------
## Static Variables - won't change for each implementation of this runbook
$nsgresourcegroup = "$prefix-dr-srv-rg" # statically set based on naming convention
$rulename = "drrdp_any_rdp"
$ports = @("3389")
$rdpIP = $first3octets + ".10"
## End Static Variables
## ------------

# Define NSG's to apply the rule to, by getting all in the resource group and then removing subnets we don't care about
$nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $nsgresourcegroup
$nsgs = $nsgs | where-object { $_.Name -notlike "*lb-nsg" }

# Use 200 range for incoming DR rules according to numbering standard
$priorityrange = 200..299

ForEach ($nsg in $nsgs) {
    # Find existing priorities for all rules in this NSG
    $priorityoccupied = $nsg.SecurityRules.Priority | Where-object { $_ -In 200..299 }
    # Within the range, find the next number (starting from the beginning, not the highest)
    $newpriority = $priorityrange | where-object { $priorityoccupied -notcontains $_ } | select-object -first 1

    if ($nsg.SecurityRules.Name -ceq "$rulename") {
        try {
            $nsg | Set-AzNetworkSecurityRuleConfig -Access Allow `
                -Direction Inbound -name $rulename -Priority $newpriority `
                -DestinationAddressPrefix "*" -DestinationPortRange $ports `
                -SourceAddressPrefix $rdpIP -SourcePortRange * -Protocol * | Set-AzNetworkSecurityGroup | out-null
        write-output "DR RDP Rule updated for: $($nsg.Name)"
        }
        Catch {
            ErrorMessage = 'Failed to update rule in the Network Security Group.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                -ErrorAction Stop$
        }
    }
    else {
        try {
            $nsg | Add-AzNetworkSecurityRuleConfig -Access Allow `
                -Direction Inbound -name $rulename -Priority $newpriority `
                -DestinationAddressPrefix "*" -DestinationPortRange $ports `
                -SourceAddressPrefix $rdpIP -SourcePortRange * -Protocol * | Set-AzNetworkSecurityGroup | out-null
        write-output "DR RDP Rule added for: $($nsg.Name)"
        }
        Catch {
            ErrorMessage = 'Failed to add rule in the Network Security Group.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                -ErrorAction Stop$
        }
    }
}