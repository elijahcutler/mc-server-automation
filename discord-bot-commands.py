import logging
import asyncio
import config

import discord
from discord.ext import commands
from discord_interactions import SlashCommand, SlashContext

from azure.identity import ClientSecretCredential
from azure.mgmt.compute import ComputeManagementClient

from mcstatus import JavaServer

logging.basicConfig(level=logging.ERROR)

# Discord bot token
discord_token = config.discord_token

# Minecraft channel
channel_id = config.channel_id
approved_role = config.approved_role

# Azure credentials
client_id = config.client_id
client_secret = config.client_secret
tenant_id = config.tenant_id
subscription_id = config.subscription_id

# Azure resource information
resource_group_name = config.resource_group_name
vm_name = config.vm_name

# Minecraft server information
minecraft_server_host = config.minecraft_server_host
minecraft_server_port = config.minecraft_server_port
minecraft_rcon_port = config.minecraft_rcon_port
minecraft_rcon_password = config.minecraft_rcon_password

# Authenticate using ClientSecretCredential
credentials = ClientSecretCredential(client_id=client_id, client_secret=client_secret, tenant_id=tenant_id)

# Create a Compute Management Client
compute_client = ComputeManagementClient(credentials, subscription_id)

intents = discord.Intents.default()
intents.message_content = True

bot = commands.Bot(command_prefix='!', intents=intents)

@bot.event
async def on_ready():
    # Set the bot's activity status
    activity = discord.Game(name="/startmc")
    await bot.change_presence(status=discord.Status.online, activity=activity)
    print(f'Logged in as {bot.user}')
    for guild in bot.guilds:
        print(f'{bot.user} is connected to the following guild:\n'
              f'{guild.name}(id: {guild.id})')

@bot.command(name='startmc')
async def start_mc(ctx):
    if ctx.channel.id != channel_id:
        return
    
    await ctx.send('Checking VM status...')
    
    # Get VM instance view to check status
    instance_view = compute_client.virtual_machines.instance_view(resource_group_name, vm_name)
    statuses = instance_view.statuses
    vm_status = next((status.code for status in statuses if status.code.startswith('PowerState/')), None)
    
    if vm_status == 'PowerState/running':
        # Check if Minecraft server is running
        try: 
            server = get_minecraft_server_details(mc_hostname)
            await ctx.send(f"Minecraft server status: ONLINE ({mc_hostname}, {server.version.name}")
        except: 
            await ctx.send(f"Minecraft server status: OFFLINE (or unreachable)")
    else:
        await ctx.send('The VM is not running. Starting the VM...')
        async with ctx.typing():
            async def start_vm():
                compute_client.virtual_machines.begin_start(resource_group_name, vm_name).result()
                return compute_client.virtual_machines.instance_view(resource_group_name, vm_name)

            try:
                instance_view = await start_vm()
                statuses = instance_view.statuses
                vm_status = next((status.code for status in statuses if status.code.startswith('PowerState/')), None)
                if vm_status == 'PowerState/running':
                    await ctx.send('The VM has been started successfully. Waiting a bit before checking Minecraft server status...')
                    await asyncio.sleep(60)

                    # Check if Minecraft server is running
                    try: 
                        server = get_minecraft_server_details(mc_hostname)
                        await ctx.send(f"Minecraft server status: ONLINE ({mc_hostname}, {server.version.name}")
                    except: 
                        await ctx.send(f"Minecraft server status: OFFLINE (or unreachable)")
                else:
                    await ctx.send('The VM could not be started. Please check the Azure portal for more details.')
            except Exception as e:
                await ctx.send(f'An error occurred while starting the VM: {str(e)}')

########################################################################################################

def get_minecraft_server_details(host, port=25565):
    try:
        return JavaServer.lookup(f"{host}:{port}").status()
    except OSError as e:
        logging.error(f"Error getting server status: {e}")
        raise e
    