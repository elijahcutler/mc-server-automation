"""An Azure RM Python Pulumi program"""

import pulumi
import pulumi_azure as azure

resource_group = azure.core.ResourceGroup("resource-group", location="eastus")
storage_account = azure.storage.Account(
	"storage-account",
	resource_group_name=resource_group.name,
	location=resource_group.location,
	account_tier="Standard",
	account_replication_type="LRS")
service_plan = azure.appservice.ServicePlan(
	"service-plan",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    os_type="Linux",
    sku_name="B1")
functionApp = azure.appservice.LinuxFunctionApp(
	"function-app",
	resource_group_name=resource_group.name,
    location=resource_group.location,
    storage_account_name=storage_account.name,
    storage_account_access_key=storage_account.primary_access_key,
    service_plan_id=service_plan.id,
    site_config=azure.appservice.LinuxWebAppSiteConfigArgs(
        always_on=False
    ))

pulumi.export("functionAppName", functionApp.name)
