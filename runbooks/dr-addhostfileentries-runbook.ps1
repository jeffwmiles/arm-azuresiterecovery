<#
 .Synopsis
  Perform a VMRun command on RDP server to add host file entries

 .Description
 Useful when you are performing an Azure Site Recovery Test Failover into an isolated environment which will not have
 any original DNS resolution, but your test plan requires using pre-existing hostnames.
 Ideally your DNS resolution would also be part of your Test Failover

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
$test_dnsname = Get-AutomationVariable -Name 'test_dnsname'
# End Automation Variables
## ------------

## ------------
## Static Variables - won't change for each implementation of this runbook
$resourcegroupname = "$($prefix)-dr-*"
## End Static Variables
## ------------

# Add star to ensure that we capture the "test" rdp server
$VM = Get-AzVm -Name "$($prefix)-rdp1*" -ResourceGroupName $resourcegroupname

# Invoke a command inside the VM, to run PowerShell which will update the Host file
$commandpath = ".\AddHostFileEntry.ps1"
$remoteCommand =
@'
    param (
    [string]$First3Octets,
    [string]$prodexternal_dnsname,
    [string]$test_dnsname
    )

    # Define static IPs for IIS binding on web server #1, based on numbering standard
    $testintIP = "$($First3Octets).39"

    #Write to Host File:
    Add-Content -Path C:\Windows\System32\Drivers\etc\hosts -value "$($testintIP)    $($test_dnsname)"
'@

# Save the command to a local file
Write-Output ("Write VMRunCommand locally.")
Set-Content -Path $commandpath -Value $remoteCommand
# Invoke the command on the VM, using the local file
$runcmdparameters = @{
    "First3Octets"         = $first3octets;
    "test_dnsname" = $test_dnsname;
}
Invoke-AzVMRunCommand -Name $VM.Name -ResourceGroupName $VM.resourcegroupname -CommandId 'RunPowerShellScript' -ScriptPath $commandpath -Parameter $runcmdparameters
Write-Output ("Invoked the VMRunCommand.")
# Clean-up the local file
Remove-Item $commandpath
