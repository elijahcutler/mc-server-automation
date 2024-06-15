import os
import discord
import socket
import asyncio
import logging
from rcon.source import Client
from mcstatus import JavaServer
from discord.ext import commands
from azure.identity import ClientSecretCredential
from azure.mgmt.compute import ComputeManagementClient

import config

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
    activity = discord.Game(name="!startmc")
    await bot.change_presence(status=discord.Status.online, activity=activity)
    print(f'Logged in as {bot.user}')
    for guild in bot.guilds:
        print(f'{bot.user} is connected to the following guild:\n'
              f'{guild.name}(id: {guild.id})')

# Command to power on the VM and check if Minecraft server has started
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
        server_running = check_minecraft_server_status(minecraft_server_host, minecraft_server_port)
        if server_running:
            version = get_minecraft_server_version(minecraft_server_host)

            if version is None:
                await ctx.send("Failed to retrieve Minecraft server version.")
            else:
                await ctx.send(f"The Minecraft server ({minecraft_server_host}, {version}) is currently running.")
        else:
            await ctx.send('The VM is powered on, but the Minecraft server is not running. Please start the server manually.')

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
                    await ctx.send('The VM has been started successfully. Waiting 1 minute before checking Minecraft server status...')

                    await asyncio.sleep(60)

                    # Check if Minecraft server is running
                    server_running = check_minecraft_server_status(minecraft_server_host, minecraft_server_port)
                    version = get_minecraft_server_version(minecraft_server_host)
                    if server_running:
                        await ctx.send(f"The Minecraft server ({minecraft_server_host}, {version}) is now running!")
                    else:
                        await ctx.send('The VM is running, but the Minecraft server is not active. Please start the server manually.')

                else:
                    await ctx.send('The VM could not be started. Please check the Azure portal for more details.')
            except Exception as e:
                await ctx.send(f'An error occurred while starting the VM: {str(e)}')

# Command to stop the Minecraft server and shut down the VM
@bot.command(name='stopmc')
@commands.has_role(approved_role)
async def stop_mc(ctx):
    await ctx.send("Stopping Minecraft server...")
    if await stop_minecraft_server():
        await ctx.send("Minecraft server stopped. Shutting down VM...")
        if await shutdown_vm():
            await ctx.send("VM has been shut down.")
        else:
            await ctx.send("Failed to shut down VM.")
    else:
        await ctx.send("Failed to stop Minecraft server.")

# Error handler for missing role
@stop_mc.error
async def stop_mc_error(ctx, error):
    if isinstance(error, commands.MissingRole):
        await ctx.send("You do not have the required role to use this command.")

async def stop_minecraft_server():
    try:
        with Client(minecraft_server_host, minecraft_rcon_port, passwd=minecraft_rcon_password) as client:
            response = client.run('stop')
            logging.info(response)
    except Exception as e:
        logging.error(f"Error stopping Minecraft server: {e}")
        return False
    return True

async def shutdown_vm():
    try:
        async_vm_shutdown = compute_client.virtual_machines.begin_power_off(resource_group_name, vm_name)
        async_vm_shutdown.wait()
    except Exception as e:
        logging.error(f"Error shutting down VM: {e}")
        return False
    return True

def check_minecraft_server_status(host, port):
    try:
        with socket.create_connection((host, port), timeout=5):
            return True
    except (socket.timeout, ConnectionRefusedError, OSError):
        return False

def get_minecraft_server_version(host):
    try:
        server = JavaServer.lookup(host)
        status = server.status()
        return status.version.name
    except OSError as e:
        logging.error(f"Error getting server status: {e}")
        return None

bot.run(discord_token)
