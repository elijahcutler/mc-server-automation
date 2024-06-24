import os
import discord
import socket
import asyncio
import logging
import random
import boto3
from rcon.source import Client
from mcstatus import JavaServer
from discord.ext import commands, tasks

import config

logging.basicConfig(level=logging.ERROR)

# Discord bot token
discord_token = config.discord_token

# Minecraft channel
channel_id = config.channel_id
approved_role = config.approved_role

# AWS credentials
aws_access_key = config.aws_access_key
aws_secret_key = config.aws_secret_key
aws_region = config.aws_region

# AWS EC2 instance information
ec2_instance_id = config.ec2_instance_id

# Minecraft server information
minecraft_server_host = config.minecraft_server_host
minecraft_server_port = config.minecraft_server_port
minecraft_rcon_port = config.minecraft_rcon_port
minecraft_rcon_password = config.minecraft_rcon_password

# Initialize boto3 client
ec2_client = boto3.client(
    'ec2',
    aws_access_key_id=aws_access_key,
    aws_secret_access_key=aws_secret_key,
    region_name=aws_region
)

intents = discord.Intents.default()
intents.message_content = True

bot = commands.Bot(command_prefix='!', intents=intents)

@tasks.loop(seconds=60)
async def update_status():
    try:
        server = JavaServer.lookup(minecraft_server_host)
        status = server.status()
        activity = discord.Game(f"📶🟢 | 👥: {status.players.online} | v{status.version.name}")
    except:
        activity = discord.Game("📶🔴 | !startmc")

    await bot.change_presence(status=discord.Status.online, activity=activity)

@bot.event
async def on_ready():
    # Set the bot's activity status
    activity = discord.Game(name="!startmc")
    await bot.change_presence(status=discord.Status.online, activity=activity)
    print(f'Logged in as {bot.user}')
    for guild in bot.guilds:
        print(f'{bot.user} is connected to the following guild:\n'
              f'{guild.name}(id: {guild.id})')
    update_status.start()

@bot.command(name='startmc')
async def start_mc(ctx):
    if ctx.channel.id != channel_id:
        return

    # React with hourglass when the operation starts
    await ctx.message.add_reaction('⏳')

    # Get EC2 instance status
    response = ec2_client.describe_instance_status(InstanceIds=[ec2_instance_id])
    instance_status = response['InstanceStatuses'][0]['InstanceState']['Name'] if response['InstanceStatuses'] else 'stopped'
    
    if instance_status == 'running':
        server_running = check_minecraft_server_status(minecraft_server_host, minecraft_server_port)
        if server_running:
            await ctx.message.remove_reaction('⏳', bot.user)
            await ctx.message.add_reaction('✅')
        else:
            await ctx.message.remove_reaction('⏳', bot.user)
            await ctx.message.add_reaction('❌')
    else:
        async with ctx.typing():
            try:
                ec2_client.start_instances(InstanceIds=[ec2_instance_id])
                await asyncio.sleep(60)  # Waiting 1 minute before checking the server status

                server_running = check_minecraft_server_status(minecraft_server_host, minecraft_server_port)
                if server_running:
                    await ctx.message.remove_reaction('⏳', bot.user)
                    await ctx.message.add_reaction('✅')
                else:
                    await ctx.message.remove_reaction('⏳', bot.user)
                    await ctx.message.add_reaction('❌')

            except Exception as e:
                await ctx.message.remove_reaction('⏳', bot.user)
                await ctx.message.add_reaction('❌')

# Command to stop the Minecraft server and shut down the EC2 instance
@bot.command(name='stopmc')
@commands.has_role(approved_role)
async def stop_mc(ctx):
    await ctx.send("Stopping Minecraft server...")
    if await stop_minecraft_server():
        await ctx.send("Minecraft server stopped. Shutting down EC2 instance...")
        if await shutdown_instance():
            await ctx.send("EC2 instance has been shut down.")
        else:
            await ctx.send("Failed to shut down EC2 instance.")
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

async def shutdown_instance():
    try:
        ec2_client.stop_instances(InstanceIds=[ec2_instance_id])
    except Exception as e:
        logging.error(f"Error shutting down EC2 instance: {e}")
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

@bot.command(name='cum', aliases=['freak', 'freaky', 'swallowmc', 'fuckshitup', 'startmcButMakeItGay'])
async def respond(ctx):
    responses=['cum', 'nasty ass', 'freaky ass', 'dont talk to me bro', 'ok', 'breed me', 
        'who gettin pegged tonite?', 'tag the best throat goat in this discord rn', 'leave me alone',
        'what if instead of Minecraft, it was :tongue: FREAKcraft :tongue:', ':tongue: hey vro', 'pee pee poo poo']
    typing_time=[1,1.5,2,2.5,3]

    if ctx.channel.id != channel_id:
        return
    async with ctx.typing():
        await asyncio.sleep(random.choice(typing_time))
        await ctx.send(random.choice(responses))

bot.run(discord_token)