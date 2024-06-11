#!/bin/bash
MC_SERVER_PATH="/home/elijahcutler/fabric-server-1.20.6/"
CHECK_INTERVAL=15 # in minutes

# Function to get the number of active players
get_player_count() {
    screen -S minecraft -X stuff "list^M"
    sleep 1
    PLAYER_COUNT=$(screen -S minecraft -X hardcopy .player_count.txt; tail -n 1 .player_count.txt | grep -oP '\d+ players online' | grep -oP '\d+')
    rm .player_count.txt
    echo "$PLAYER_COUNT"
}

# Main loop
while true; do
    PLAYER_COUNT=$(get_player_count)
    if [ "$PLAYER_COUNT" -eq 0 ]; then
        echo "No players connected. Waiting for $CHECK_INTERVAL minutes."
        sleep "${CHECK_INTERVAL}m"
        PLAYER_COUNT=$(get_player_count)
        if [ "$PLAYER_COUNT" -eq 0 ]; then
            echo "No players connected for $CHECK_INTERVAL minutes. Shutting down."
            # Stop the Minecraft server
            screen -S minecraft -X stuff "stop^M"
            sleep 60 # Wait for the server to stop gracefully
            # Shut down the system
            sudo shutdown -h now
            exit
        fi
    else
        echo "$PLAYER_COUNT players connected. Checking again in 1 minute."
        sleep 1m
    fi
done