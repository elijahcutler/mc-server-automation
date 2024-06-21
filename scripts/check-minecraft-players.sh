#!/bin/bash

# Set variables
working_directory="/home/minecraft/scripts"
rcon_ip=127.0.0.1
rcon_port=25575
rcon_password=""
idle_limit=900  # 15 minutes in seconds
log_file="${working_directory}/minecraft-idle.log"
last_active_file="${working_directory}/last-active"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}

# Check if rcon cli is installed
if ! command -v rcon &> /dev/null; then
    log_message "error: rcon cli is not installed."
    exit 1
fi

# Check for connected players
player_count=$(rcon -a ${rcon_ip}:${rcon_port} -p "${rcon_password}" list | grep -oP 'There are \d+' | awk '{print $3}')

if [[ $player_count -eq 0 ]]; then
    log_message "no players connected."
    
    # Check idle time
    if [[ -f "${last_active_file}" ]]; then
        last_active_time=$(stat -c %Y "${last_active_file}")
        current_time=$(date +%s)
        elapsed_time=$((current_time - last_active_time))

        if [[ $elapsed_time -ge $idle_limit ]]; then
            log_message "server has been idle for 15 minutes. Initiating shutdown."
            sudo rm -rf ${last_active_file}
            sudo systemctl stop minecraft.service
            sudo shutdown -h now
        fi
    else
        log_message "last active file not found. Creating now."
        touch "${last_active_file}"
    fi
else
    log_message "players connected: $player_count"
    touch "${last_active_file}"
fi
