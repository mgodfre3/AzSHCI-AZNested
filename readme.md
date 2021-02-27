


Welcome to the easiest deployment of Azure Stack HCI, full stack of your life! With this ARM Template you will be able to deploy a working, nested Azure Stack HCI cluster with Hyper-V, Storage Spaces Direct and Software Defined Networking, all manged by Windows Admin Center. It's so simple!

<!--
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.//com%2Fmgodfre3%2FAzSHCI-AZNested%2Fmain%2Fjson%2Fazuredeploy.json
)
--> 



This deployment will need to happen with PowerShell or Windows Terminal. This is an easy process, but it will require you have a few things.

-An Azure Subscription with Permissions to create a Resource Group and at least Contributor Permissions on that Resource Group

-the AZ Powershell Module, simply run Install-Module -Name AZ in your Powershell session.

-Copy of the code, located in this repository.

First, you will need to login to your Azure Account in your Terminal Session.

Login-AZAccount

Then you will need to select your Subscription

Select-AZSubscription -Subscription "XXXXXXXX"

Following that, you will want to create a Resource Group Name Variable, something like:

$rg=Get-AZResourceGroupName -Name "ASHCI-Deployment"

then you need a password, strored as a variable, dont forget it, you will need it to login to the VM we create.

$password=ConvertTo-SecureString -String "Password" -AsPlainText -Force

Now store the template files as variables. Try something like

$template=<path to azuredeploy.json>
$paramTemplate=<path to azuredeploy.parameters.json>

Phew, we are ready to deploy. Ready, here we go.

New-AzResourceGroupDeployment -Name ASHCINestedDeployment -ResourceGroupName $rg.resourcegroupname -TemplateFile $template -TemplateParameterFile $paramTemplate -AdminPassword $password 


Give this a couple of minutes, and you will see your new VM, ASHCIHost001 if you kept the default name, in your Resource group. You can RDP to the Public IP address and then begin the deployment of the cluster, this first step was only to deploy the Host, the real fun begins next but dont worry it really is easy.




