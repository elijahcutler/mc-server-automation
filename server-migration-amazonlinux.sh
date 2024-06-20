#!/bin/bash

# Ensure the script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Variables
DROPBOX_URL="your_dropbox_shared_link_here"
RCON_URL="https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz"
SCRIPT_NAME="$(basename "$0")"

# Function to install a package if not already installed
install_package() {
    local pkg=$1
    if ! command -v $pkg &>/dev/null; then
        echo "$pkg is not installed. Installing $pkg..."
        yum install -y $pkg
    else
        echo "$pkg is already installed."
    fi
}

# Function to start and enable a service if not already enabled
start_and_enable_service() {
    local service_name=$1
    systemctl start "$service_name"
    if [ $? -ne 0 ]; then
        echo "Failed to start $service_name."
        exit 1
    fi
    if ! systemctl is-enabled "$service_name" &>/dev/null; then
        systemctl enable "$service_name"
    fi
}

# Function to make scripts executable
make_scripts_executable() {
    for script in check-minecraft-players.sh manual-start-server.sh; do
        if [ -f /home/minecraft/server/$script ] && [ ! -x /home/minecraft/server/$script ]; then
            chmod +x /home/minecraft/server/$script
        fi
    done
}

# Function to check the status of services
check_service_status() {
    local services=("minecraft.service" "minecraft-shutdown.service" "minecraft-shutdown.timer")
    for service in "${services[@]}"; do
        echo "Checking status of $service"
        systemctl status "$service"
    done
}

# Install necessary packages
install_package firewalld
install_package java-21-openjdk

# Check if rcon is installed, if not then install it
check_and_install_rcon() {
    if ! command -v rcon &>/dev/null; then
        echo "Installing rcon..."
        wget -O /home/minecraft/downloads/rcon.tar.gz $RCON_URL
        tar -xzvf /home/minecraft/downloads/rcon.tar.gz -C /home/minecraft/downloads
        mv /home/minecraft/downloads/rcon-0.10.3-amd64_linux/rcon /usr/local/bin/rcon
        chmod +x /usr/local/bin/rcon
        rm -rf /home/minecraft/downloads/rcon.tar.gz /home/minecraft/downloads/rcon-0.10.3-amd64_linux

        # Add rcon to the PATH
        if ! grep -q "/usr/local/bin" <<< "$PATH"; then
            echo "export PATH=\$PATH:/usr/local/bin" >> /etc/profile
            source /etc/profile
        fi
    else
        echo "rcon is already installed."
    fi
}

# Check and install rcon
check_and_install_rcon

# Firewall configuration
firewall-cmd --zone=public --add-port=25565/tcp --permanent
firewall-cmd --zone=public --add-port=25575/tcp --permanent
firewall-cmd --reload

# Create user 'minecraft' if it does not exist
if ! id -u minecraft >/dev/null 2>&1; then
    useradd -m minecraft
    echo "minecraft ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/minecraft
    usermod -aG wheel minecraft
fi

# Create downloads directory
mkdir -p /home/minecraft/downloads
chown minecraft:minecraft /home/minecraft/downloads

# Check if /home/minecraft/server/ and /home/minecraft/services-backup/ exist
if [ -d /home/minecraft/server ] && [ -d /home/minecraft/services-backup ]; then
    echo "/home/minecraft/server and /home/minecraft/services-backup already exist. Skipping download and extraction steps."
    make_scripts_executable
    start_and_enable_service minecraft.service
    start_and_enable_service minecraft-shutdown.service
    start_and_enable_service minecraft-shutdown.timer
    check_service_status
    exit 0
fi

# Download and unzip the server files
DROPBOX_DIRECT_URL=${DROPBOX_URL/\?dl=0/\?dl=1}
wget -O /home/minecraft/downloads/mc-server-files.zip $DROPBOX_DIRECT_URL
unzip /home/minecraft/downloads/mc-server-files.zip -d /home/minecraft/downloads
chown -R minecraft:minecraft /home/minecraft/downloads

# Get the extracted folder name
EXTRACTED_FOLDER=$(find /home/minecraft/downloads -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | grep -v '^downloads$')

# Validate the required directories and service files
if [ ! -d /home/minecraft/downloads/$EXTRACTED_FOLDER/server ] || [ ! -d /home/minecraft/downloads/$EXTRACTED_FOLDER/services ]; then
    echo "Error: Required directories 'server' or 'services' not found in the extracted folder."
    exit 1
fi

if ! ls /home/minecraft/downloads/$EXTRACTED_FOLDER/services/*.service &>/dev/null; then
    echo "Error: No service files found in the 'services' directory."
    exit 1
fi

# Prompt for overwrite if /home/minecraft/server exists
if [ -d /home/minecraft/server ]; then
    read -p "/home/minecraft/server already exists. Do you want to overwrite it? (Y/N): " choice
    case "$choice" in
        y|Y ) rm -rf /home/minecraft/server;;
        n|N ) echo "Skipping server directory overwrite."; exit 0;;
        * ) echo "Invalid choice. Exiting."; exit 1;;
    esac
fi

# Move server directory and backup services
mv /home/minecraft/downloads/$EXTRACTED_FOLDER/server /home/minecraft
chown -R minecraft:minecraft /home/minecraft/server
mkdir -p /home/minecraft/services-backup
cp -r /home/minecraft/downloads/$EXTRACTED_FOLDER/services/* /home/minecraft/services-backup/
chown -R minecraft:minecraft /home/minecraft/services-backup
mv /home/minecraft/downloads/$EXTRACTED_FOLDER/services/* /etc/systemd/system/

# Ensure scripts are executable
make_scripts_executable

# Enable and start the services
start_and_enable_service minecraft.service
start_and_enable_service minecraft-shutdown.service
start_and_enable_service minecraft-shutdown.timer

# Check the status of services
check_service_status

# Clean up the downloads folder except the script itself
find /home/minecraft/downloads/* ! -name "$SCRIPT_NAME" -exec rm -rf {} +

# Wait for one minute before reboot
echo "Waiting for one minute before reboot..."
sleep 60

# Initialize a reboot
reboot
