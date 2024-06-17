"""An Azure RM Python Pulumi program"""

import pulumi
import pulumi_azure as azure
import pulumi_azure_native as azure_native
import pulumi_command as command


config = pulumi.Config()
public_key = config.get('publicKey')
admin_username = config.get('admin_username')
admin_password = config.get('admin_password')


def decode_key(key):
    if key.startswith('-----BEGIN RSA PRIVATE KEY-----'):
        return key
    return key.encode('ascii')


private_key = config.require_secret('privateKey').apply(decode_key)

resource_group = azure.core.ResourceGroup("resource-group", location="eastus")
storage_account = azure.storage.Account(
    "storage-account",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    account_tier="Standard",
    account_replication_type="LRS")
# TODO: add this back when I am no longer rate limited by Azure 😛
# service_plan = azure.appservice.ServicePlan(
#     "service-plan",
#     resource_group_name=resource_group.name,
#     location=resource_group.location,
#     os_type="Linux",
#     sku_name="Y1")
# functionApp = azure.appservice.LinuxFunctionApp(
#     "function-app",
#     resource_group_name=resource_group.name,
#     location=resource_group.location,
#     storage_account_name=storage_account.name,
#     storage_account_access_key=storage_account.primary_access_key,
#     service_plan_id=service_plan.id,
#     site_config=azure.appservice.LinuxWebAppSiteConfigArgs(
#         always_on=False
#     ))
#
# pulumi.export("functionAppName", functionApp.name)

net = azure_native.network.VirtualNetwork(
    "server-network",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    address_space=azure_native.network.AddressSpaceArgs(
        address_prefixes=["10.0.0.0/16"],
    ),
    subnets=[azure_native.network.SubnetArgs(
        name="default",
        address_prefix="10.0.0.0/24",
    )]
)

public_ip = azure_native.network.PublicIPAddress(
    "server-ip",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    public_ip_allocation_method="Dynamic"
)

network_iface = azure_native.network.NetworkInterface(
    "server-nic",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    ip_configurations=[azure_native.network.NetworkInterfaceIPConfigurationArgs(
        name="webserveripcfg",
        subnet=azure_native.network.SubnetArgs(id=net.subnets[0].id),
        private_ip_allocation_method="Dynamic",
        public_ip_address=azure_native.network.PublicIPAddressArgs(
            id=public_ip.id),
    )]
)

ssh_path = "".join(["/home/", admin_username, "/.ssh/authorized_keys"])
server = azure_native.compute.VirtualMachine(
    "server-vm",
    resource_group_name=resource_group.name,
    location=resource_group.location,
    network_profile=azure_native.compute.NetworkProfileArgs(
        network_interfaces=[
            azure_native.compute.NetworkInterfaceReferenceArgs(
                id=network_iface.id),
        ],
    ),
    hardware_profile=azure_native.compute.HardwareProfileArgs(
        vm_size=azure_native.compute.VirtualMachineSizeTypes.STANDARD_B2S,
    ),
    os_profile=azure_native.compute.OSProfileArgs(
        computer_name="hostname",
        admin_username=admin_username,
        admin_password=admin_password,
        linux_configuration=azure_native.compute.LinuxConfigurationArgs(
            disable_password_authentication=False,
            ssh={
                'publicKeys': [{
                    'keyData': public_key,
                    'path': ssh_path,
                }],
            },
        ),
    ),
    storage_profile=azure_native.compute.StorageProfileArgs(
        os_disk=azure_native.compute.OSDiskArgs(
            create_option="FromImage",
            name="myosdisk1",
            caching="ReadWrite",
            disk_size_gb=30,
            # TODO: Consider detaching disk instead of deleting to enable retrieval of world files
            delete_option=azure_native.compute.DiskDeleteOptionTypes.DELETE
        ),
        image_reference=azure_native.compute.ImageReferenceArgs(
            publisher="canonical",
            offer="UbuntuServer",
            sku="18.04-LTS",
            version="latest",
        )
    )
)

public_ip_addr = server.id.apply(lambda _:
                                 azure_native.network.get_public_ip_address_output(
                                     public_ip_address_name=public_ip.name,
                                     resource_group_name=resource_group.name)
                                 )

connection = command.remote.ConnectionArgs(
    host=public_ip_addr.ip_address,
    user=admin_username,
    private_key=private_key
)
cp_config = command.remote.CopyFile(
    'config',
    connection=connection,
    local_path='../server/setup.sh',
    remote_path='setup.sh',
    opts=pulumi.ResourceOptions(depends_on=[server])
)
command.remote.Command(
    'setup',
    connection=connection,
    create='sudo chmod 755 install.sh && sudo ./setup.sh',
    opts=pulumi.ResourceOptions(depends_on=[cp_config])
)

pulumi.export("Minecraft Server IP Address", public_ip_addr.ip_address)
