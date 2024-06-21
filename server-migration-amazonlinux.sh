#!/bin/bash

# Ensure the script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Variables
DROPBOX_URL="your_dropbox_shared_link_here"
RCON_URL="https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz"
CHECK_SCRIPT_URL="https://github.com/elijahcutler/mc-server-automation/raw/main/scripts/check-minecraft-players.sh"
SERVICE_FILES=(
    "https://github.com/elijahcutler/mc-server-automation/raw/3b284134d0051ed0028f28ad216263f60ee485f0/services/minecraft.service"
    "https://github.com/elijahcutler/mc-server-automation/raw/3b284134d0051ed0028f28ad216263f60ee485f0/services/minecraft-shutdown.service"
    "https://github.com/elijahcutler/mc-server-automation/raw/3b284134d0051ed0028f28ad216263f60ee485f0/services/minecraft-shutdown.timer"
)
SCRIPT_NAME="$(basename "$0")"
DOWNLOAD_DIR="/home/minecraft/downloads"
SERVER_DIR="/home/minecraft/server"
SCRIPTS_DIR="/home/minecraft/scripts"
SERVICES_BACKUP_DIR="/home/minecraft/services-backup"
SYSTEMD_DIR="/etc/systemd/system"

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
    systemctl enable "$service_name"
}

# Function to make scripts executable
make_scripts_executable() {
    local check_script_path="$SCRIPTS_DIR/check-minecraft-players.sh"
    if [ -f "$check_script_path" ] && [ ! -x "$check_script_path" ]; then
        chmod +x "$check_script_path"
    fi
}

# Function to check the status of services
check_service_status() {
    for service in minecraft.service minecraft-shutdown.service minecraft-shutdown.timer; do
        echo "Checking status of $service"
        systemctl status "$service"
    done
}

# Function to download and install service files
install_service_files() {
    mkdir -p "$SERVICES_BACKUP_DIR"
    for url in "${SERVICE_FILES[@]}"; do
        local filename=$(basename "$url")
        wget -O "$SERVICES_BACKUP_DIR/$filename" "$url"
        cp "$SERVICES_BACKUP_DIR/$filename" "$SYSTEMD_DIR/"
    done
}

# Install necessary packages
install_package firewalld
install_package java-21-openjdk

# Check if rcon is installed, if not then install it
check_and_install_rcon() {
    if ! command -v rcon &>/dev/null; then
        echo "Installing rcon..."
        wget -O "$DOWNLOAD_DIR/rcon.tar.gz" "$RCON_URL"
        tar -xzvf "$DOWNLOAD_DIR/rcon.tar.gz" -C "$DOWNLOAD_DIR"
        mv "$DOWNLOAD_DIR/rcon-0.10.3-amd64_linux/rcon" /usr/local/bin/rcon
        chmod +x /usr/local/bin/rcon
        rm -rf "$DOWNLOAD_DIR/rcon.tar.gz" "$DOWNLOAD_DIR/rcon-0.10.3-amd64_linux"
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

# Create necessary directories
mkdir -p "$DOWNLOAD_DIR" "$SCRIPTS_DIR"
chown minecraft:minecraft "$DOWNLOAD_DIR" "$SCRIPTS_DIR"

# Download check-minecraft-players.sh
wget -O "$SCRIPTS_DIR/check-minecraft-players.sh" "$CHECK_SCRIPT_URL"
chmod +x "$SCRIPTS_DIR/check-minecraft-players.sh"
chown minecraft:minecraft "$SCRIPTS_DIR/check-minecraft-players.sh"

# Check if /home/minecraft/server/ and /home/minecraft/services-backup/ exist
if [ -d "$SERVER_DIR" ] && [ -d "$SERVICES_BACKUP_DIR" ]; then
    echo "$SERVER_DIR and $SERVICES_BACKUP_DIR already exist. Skipping download and extraction steps."
    make_scripts_executable
    install_service_files
    start_and_enable_service minecraft.service
    start_and_enable_service minecraft-shutdown.service
    start_and_enable_service minecraft-shutdown.timer
    check_service_status
    exit 0
fi

# Download and unzip the server files
DROPBOX_DIRECT_URL=${DROPBOX_URL/\?dl=0/\?dl=1}
wget -O "$DOWNLOAD_DIR/mc-server-files.zip" "$DROPBOX_DIRECT_URL"
unzip "$DOWNLOAD_DIR/mc-server-files.zip" -d "$DOWNLOAD_DIR"
chown -R minecraft:minecraft "$DOWNLOAD_DIR"

# Get the extracted folder name
EXTRACTED_FOLDER=$(find "$DOWNLOAD_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | grep -v '^downloads$')

# Validate the required directories and service files
if [ ! -d "$DOWNLOAD_DIR/$EXTRACTED_FOLDER/server" ]; then
    echo "Error: Required directory 'server' not found in the extracted folder."
    exit 1
fi

# Prompt for overwrite if /home/minecraft/server exists
if [ -d "$SERVER_DIR" ]; then
    read -p "$SERVER_DIR already exists. Do you want to overwrite it? (Y/N): " choice
    case "$choice" in
        y|Y ) rm -rf "$SERVER_DIR";;
        n|N ) echo "Skipping server directory overwrite."; exit 0;;
        * ) echo "Invalid choice. Exiting."; exit 1;;
    esac
fi

# Move server directory
mv "$DOWNLOAD_DIR/$EXTRACTED_FOLDER/server" /home/minecraft
chown -R minecraft:minecraft "$SERVER_DIR"

# Ensure only one jar file exists and rename it to server.jar
JAR_FILES=("$SERVER_DIR"/*.jar)
if [ ${#JAR_FILES[@]} -eq 0 ]; then
    echo "Error: No .jar file found in the server directory."
    exit 1
elif [ ${#JAR_FILES[@]} -gt 1 ]; then
    echo "Error: Multiple .jar files found in the server directory. Please ensure only one .jar file is present."
    exit 1
else
    mv "${JAR_FILES[0]}" "$SERVER_DIR/server.jar"
fi

# Install service files
install_service_files

# Ensure scripts are executable
make_scripts_executable

# Enable and start the services
start_and_enable_service minecraft.service
start_and_enable_service minecraft-shutdown.service
start_and_enable_service minecraft-shutdown.timer

# Check the status of services
check_service_status

# Clean up the downloads folder except the script itself
find "$DOWNLOAD_DIR"/* ! -name "$SCRIPT_NAME" -exec rm -rf {} +

# Wait for one minute before reboot
echo "Waiting for one minute before reboot..."
sleep 60

# Initialize a reboot
reboot
