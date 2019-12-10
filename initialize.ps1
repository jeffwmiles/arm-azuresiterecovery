
## This script is used to deploy and set up Azure Site Recovery.
## It is intended to be run following Terraform deployment which includes required DR components

# Pre-Existing authentication to Azure in a Shell needs to exist before running this script
    # This will be enhanced in the future with a try/catch block

param(
    [parameter(Mandatory = $false)]
    [string]$prefix = "<ABC>",
    [parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "$prefix-dr-srv-rg", # this is the RG that ASR will be built under
    [parameter(Mandatory = $false)]
    [string]$tenantid = "<tenantID>",
    [parameter(Mandatory = $false)]
    [string]$subscription_id = "<subscriptionid>"
)

Select-AzSubscription -SubscriptionId $subscription_id -tenantid $tenantid

# Test to make sure resource groups and some pre-req resources are created (done previously through Terraform)
$tests = @()
if ($null -eq (get-azresourcegroup -name "$prefix-srv-rg" -erroraction Ignore)) { $tests += "false" } else { $tests += "true" }
if ($null -eq (get-azresourcegroup -name "$prefix-dr-mgmt-rg" -erroraction Ignore)) { $tests += "false" } else { $tests += "true" }
if ($null -eq (get-azresourcegroup -name "$prefix-dr-web-rg" -erroraction Ignore)) { $tests += "false" } else { $tests += "true" }
if ($null -eq (get-azresource -name "$prefix-ads-dr-avset" -erroraction Ignore)) { $tests += "false" } else { $tests += "true" }
if ($null -eq (get-azresource -name "$prefix-web-dr-avset" -erroraction Ignore)) { $tests += "false" } else { $tests += "true" }

if ($tests.Contains("false")) {
    # There was at least one test that failed, don't proceed
    write-host "There was at least one pre-requisite resource test that failed, will not proceed" -ForegroundColor Red
    write-host "Make sure your Terraform config includes the Disaster Recovery files, and re-run Terraform first." -ForegroundColor Yellow
}
else {
    # Test is all true, now check the ARM template validation
    write-host "Pre-requisite tests passed, proceeding with ARM validation" -ForegroundColor Green
    $testarm = Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile .\azuredeploy.json -TemplateParameterFile .\azuredeploy.parameters.json
    if (!$null -eq $testarm) {
        write-host "ARM template validation has failed. Output will follow, please investigate and retry" -ForegroundColor Red
        $testarm
    }
    else {
        # testarm was empty
        write-host "ARM validation passed, proceeding with ARM deployment" -ForegroundColor Green

        # Remove Resource Group Locks
        Write-Host "Removing Resource Group Locks" -ForegroundColor Yellow
        # Dependencies in Terraform for this are complex, so it was moved to the Wrapper script

        # Get all resource groups in this subscription:
        $rgs = Get-AzResourceGroup | where-object { ($_.ResourceGroupName -notlike "*-dr-*") -and ($_.ResourceGroupName -notlike "*AzureBackupRG*")  } # Can't touch Locks on DR because it'll break ASR, and on AzureBackupRG because it'll break Azure Backup
        foreach ($rg in $rgs) {
            $lockId = (Get-AzResourceLock -ResourceGroupName $rg.ResourceGroupName).LockId
            $lockId = $lockId | where-object { $_ -notlike "*ASR-Lock*"} # Don't try and manipulate ASR locks
            if ($lockId) {
                Remove-AzResourceLock -LockId $lockId -Force | Out-Null
            }
        }
        # The ARM template for a Recovery Plan isn't idempotent - if it already exists the deployment will fail.
        Write-Host "Removing the Isolated Test Failover Plan (ARM doesn't allow updates)..."
        $vault = Get-AzRecoveryServicesVault -name "$prefix-dr-rsv"
        set-azrecoveryservicesasrvaultcontext -Vault $vault
        $plan = Get-AzRecoveryServicesAsrRecoveryPlan -Name "Isolated-test-failover-plan" -ErrorAction Ignore
        if ($plan) {
            # Plan exists, so we'll remove it
            Remove-AzRecoveryServicesAsrRecoveryPlan -RecoveryPlan $plan
            Write-Host "Plan removal completed." -ForegroundColor Green
        }
        else {
            Write-Host "No recovery plan currently exists" -ForegroundColor Green
        }

        Write-Host "ARM deployment underway, this may take some time ..."
        Write-Host "You can view deployment progress in the Portal under resource group <prefix>-dr-srv-rg -> Deployments"
        $datestamp = get-date -Format "yyyy-MM-dd.hh.mm"
        New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name "$($prefix)_DR_Deploy_$datestamp" -TemplateFile .\azuredeploy.json -TemplateParameterFile .\azuredeploy.parameters.json -Mode "incremental"

        Write-Host "Adding Resource Group Locks" -ForegroundColor "Yellow"
        foreach ($rg in $rgs) {
            $start = $rg.ResourceGroupName
            $text1 = $start.Substring($start.indexof("-") + 1)
            $rgsuffix = $text1.Substring($text1.indexof("-") + 1)
            New-AzResourceLock -LockName "$($prefix)-$rgsuffix-lock" -LockLevel CanNotDelete -ResourceGroupName $rg.ResourceGroupName -LockNotes "This Resource Group and its contents cannot be deleted." -Force | Out-Null
        }
        Write-Host "###" -ForegroundColor Yellow
        Write-Host "If you just created the DR Automation Account for the first time, you must go and create a RunAs account in the Azure Portal!" -ForegroundColor Yellow
        Write-Host "###" -ForegroundColor Yellow
    }
}