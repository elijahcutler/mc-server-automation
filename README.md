# Minecraft Server Automation
## Using Azure Virtual Machine Management & Discord

Runs a Discord bot that waits for commands in a channel of your choosing.

## Explanation
### !startmc
- checks if Azure VM is running
- if not, starts Azure VM and waits for a Minecraft server to start.
- this assumes you have a systemd service on your VM that launches the server .jar upon boot up.
### !stopmc
- sends a 'stop' command via RCON to the Minecraft server console (requires hostname, port, and rcon password).
- sends a power-off request to the Azure VM
- note: only users with the provided 'approved-role' in Discord can initiate this command.
