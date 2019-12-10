A full PowerShell and ARM solution for Azure Site Recovery implementation and Recovery Plan

# ARM - Azure Site Recovery

<!--- These are examples. See https://shields.io for others or to customize this set of shields. You might want to include dependencies, project status and licence info here --->
![GitHub repo size](https://img.shields.io/github/repo-size/jeffwmiles/arm-azuresiterecovery)
![GitHub contributors](https://img.shields.io/github/contributors/jeffwmiles/arm-azuresiterecovery)
![GitHub stars](https://img.shields.io/github/stars/jeffwmiles/arm-azuresiterecovery?style=social)
![GitHub forks](https://img.shields.io/github/forks/jeffwmiles/arm-azuresiterecovery?style=social)
![Twitter Follow](https://img.shields.io/twitter/follow/jwmiles5?style=social)

This is a Azure Resourcce Manager template and PowerShell script that allows Azure Administrators to deploy Azure Site Recovery for selected VMs along with a Recovery Plan for testing.

This demonstrates integration with Azure Automation runbooks in a recovery plan to perform functions like apply a Public IP, add secondary IP's to VMs, and add network security group rules.

## Prerequisites

Before you begin, ensure you have met the following requirements:
<!--- These are just example requirements. Add, duplicate or remove as required --->
* You have installed the latest version of [Az Module for Azure PowerShell](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-3.1.0)
* You are familiar with using [ARM Templates in Azure](https://docs.microsoft.com/en-us/azure/azure-resource-manager/template-deployment-overview)
* You have an understanding of [Azure Site Recovery for Azure-to-Azure](https://docs.microsoft.com/en-us/azure/site-recovery/azure-to-azure-architecture)

* Have a source environment that matches the definition in the ARM template (VM name structure primarily)

    | Type        | Name           | ResourceGroup  |
    | ------------- |:-------------:| -----:|
    | Virtual Machine      | $prefix-ads1      | $prefix-mgmt-rg |
    | Virtual Machine      | $prefix-rdp1      |   $prefix-mgmt-rg |
    | Virtual Machine      | $prefix-web1      |   $prefix-web-rg |
    | Virtual Machine      | $prefix-web2      |   $prefix-web-rg |
    | Virtual Network      | $prefix-vnet      |   $prefix-srv-rg |

## Assumptions

This initialize script and ARM Template was written for a specific envionment design, and I haven't removed all of the assumptions from that environment. This includes:
* Pre-Creation of resources required for ASR, including destination side resource groups, virtual networks, and availability sets
    * includes storage account that runbook PS1 files have been uploaded into as blobs, under a container named 'dr-runbooks'
* Resource group locks exist on Source resources, which are removed and re-applied as part of the deployment
* Not fully-scripted creation of a Run-As account for the Automation Account runbooks are stored and executed from

Hopefully leaving in these components will serve as a reference for others to build upon.

## Using this Template

To use this ARM template, follow these steps:

1. Clone/Download the contents of the repository locally or in Azure Cloud Shell
2. Update the parameter values in `parameters.json`
3. Run `Login-AzAccount` and authenticate to your Azure tenant
4. Run to deploy:
```
.\initialize.ps1 `
    -prefix <unique prefix for environment> `
    -ResourceGroupName <rg where ASR components will be placed> `
    -tenantid <Azure AD tenant ID> `
    -subscription_id < Subid under which ASR is deployed`
```

5. Manually create a Run-As account for the Automation Account that was created
6. Configure Recovery Services Vault diagnostic settings to store ASR logs in Log Analytics workspace (manual step)
7. Modify `dashboard.json` to include the following:
    * SubscriptionId
    * ResourceGroup
    * Log Analytics workspace name
    * ResourceId of Log Analytics workspace

    Do this on:
    * Lines 19->22
    * Lines 95->98
    * Lines 184->187
    * Lines 273->276

8. Import `dashboard.json` as an [Azure Dashboard](https://docs.microsoft.com/en-us/azure/azure-portal/azure-portal-dashboards)
9. Manually run the runbook `dr-enableextensionupdate` from the Azure Automation Account, to enable ASR extension updates

## Contributing to this Template

### Items for improvement
* Iterate over a list of Virtual Machines, rather than specifying them each individually
* Include an Azure Run-As account creation
* Integrate into a Build and Release Pipeline in Azure DevOps with YAML definition

To contribute follow these steps:

1. Fork this repository.
2. Create a branch: `git checkout -b <branch_name>`.
3. Make your changes and commit them: `git commit -m '<commit_message>'`
4. Push to the original branch: `git push origin <project_name>/<location>`
5. Create the pull request.

Alternatively see the GitHub documentation on [creating a pull request](https://help.github.com/en/github/collaborating-with-issues-and-pull-requests/creating-a-pull-request).

## Helpful sources

I built this template through much trial and error, but I did use a couple of sources that gave me a leg up:

* [https://github.com/pratap-dotnet/azure-site-recovery-automation/tree/master/201-azure-site-recovery-existing-vms-replication](https://github.com/pratap-dotnet/azure-site-recovery-automation/tree/master/201-azure-site-recovery-existing-vms-replication)
    * [Blog post](https://www.cloudmanav.com/azure/azure-site-recovery-replicating-existing-vms/#)
* [https://github.com/Azure/azure-quickstart-templates/tree/master/azmgmt-demo](https://github.com/Azure/azure-quickstart-templates/tree/master/azmgmt-demo)

## Contact

If you want to contact me you can reach me on [Twitter](https://twitter.com/jwmiles5)
