#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Function to install a package if not already installed
install_package() {
    local pkg=$1
    if ! command -v $pkg &>/dev/null; then
        echo "$pkg is not installed. Installing $pkg..."
        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y $pkg
        elif command -v yum &> /dev/null; then
            yum install -y $pkg
        else
            echo "Neither apt-get nor yum found. Please install $pkg manually."
            exit 1
        fi
    else
        echo "$pkg is already installed."
    fi
}

# Install necessary packages
install_package firewalld
install_package java-21-openjdk
install_package jq

# Variables
RCON_URL="https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz"
CHECK_SCRIPT_URL="https://github.com/elijahcutler/mc-server-automation/raw/main/scripts/check-minecraft-players.sh"
SERVICE_FILES=(
    "https://github.com/elijahcutler/mc-server-automation/raw/3b284134d0051ed0028f28ad216263f60ee485f0/services/minecraft.service"
    "https://github.com/elijahcutler/mc-server-automation/raw/3b284134d0051ed0028f28ad216263f60ee485f0/services/minecraft-shutdown.service"
    "https://github.com/elijahcutler/mc-server-automation/raw/3b284134d0051ed0028f28ad216263f60ee485f0/services/minecraft-shutdown.timer"
)
DOWNLOAD_DIR="/home/minecraft/downloads"
SERVER_DIR="/home/minecraft/server"
SCRIPTS_DIR="/home/minecraft/scripts"
SERVICES_BACKUP_DIR="/home/minecraft/services-backup"
SYSTEMD_DIR="/etc/systemd/system"
EULA_URL="https://github.com/elijahcutler/mc-server-automation/raw/main/server/.defaults/eula.txt"
SERVER_PROPERTIES_URL="https://github.com/elijahcutler/mc-server-automation/raw/main/server/.defaults/server.properties"

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
mkdir -p "$DOWNLOAD_DIR" "$SCRIPTS_DIR" "$SERVER_DIR" "$SERVICES_BACKUP_DIR"
chown minecraft:minecraft "$DOWNLOAD_DIR" "$SCRIPTS_DIR" "$SERVER_DIR" "$SERVICES_BACKUP_DIR"

# Check and install rcon
check_and_install_rcon

# Download check-minecraft-players.sh
wget -O "$SCRIPTS_DIR/check-minecraft-players.sh" "$CHECK_SCRIPT_URL"
chmod +x "$SCRIPTS_DIR/check-minecraft-players.sh"
chown minecraft:minecraft "$SCRIPTS_DIR/check-minecraft-players.sh"

# Prompt user for setup type
echo "Select setup type:"
echo "1) Set up new server"
echo "2) Restore from pre-configured server zip file"
read -p "Enter your choice (1-2): " setup_choice

# Function to download the Paper server jar
download_paper() {
    read -p "Enter the Paper version you want to download: " version
    build_number=$(curl -s https://api.papermc.io/v2/projects/paper/versions/$version | jq -r '.builds[-1]')
    echo "Downloading Paper version $version build $build_number..."
    curl -o /home/minecraft/server/server.jar https://api.papermc.io/v2/projects/paper/versions/$version/builds/$build_number/downloads/paper-$version-$build_number.jar

    # Download eula.txt and server.properties
    wget -O /home/minecraft/server/eula.txt $EULA_URL
    wget -O /home/minecraft/server/server.properties $SERVER_PROPERTIES_URL
}

# Function to download the Fabric server jar
download_fabric() {
    read -p "Enter the Fabric version you want to download: " version
    installer_version=$(curl -s https://meta.fabricmc.net/v2/versions/installer | jq -r '.[0].version')
    echo "Downloading Fabric installer version $installer_version..."
    curl -o /home/minecraft/server/fabric-installer.jar https://maven.fabricmc.net/net/fabricmc/fabric-installer/$installer_version/fabric-installer-$installer_version.jar
    java -jar /home/minecraft/server/fabric-installer.jar server -mcversion $version -dir /home/minecraft/server
    rm /home/minecraft/server/fabric-installer.jar

    # Download eula.txt and server.properties
    wget -O /home/minecraft/server/eula.txt $EULA_URL
    wget -O /home/minecraft/server/server.properties $SERVER_PROPERTIES_URL
}

# Function to download the Forge server jar
download_forge() {
    read -p "Enter the Forge version you want to download: " version
    forge_version=$(curl -s https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json | jq -r --arg version "$version" '.promos[$version + "-recommended"]')
    echo "Downloading Forge version $version-$forge_version..."
    curl -o /home/minecraft/server/forge-installer.jar https://maven.minecraftforge.net/net/minecraftforge/forge/$version-$forge_version/forge-$version-$forge_version-installer.jar
    java -jar /home/minecraft/server/forge-installer.jar --installServer
    rm /home/minecraft/server/forge-installer.jar

    # Download eula.txt and server.properties
    wget -O /home/minecraft/server/eula.txt $EULA_URL
    wget -O /home/minecraft/server/server.properties $SERVER_PROPERTIES_URL
}

# Function to download the Vanilla server jar
download_vanilla() {
    read -p "Enter the Vanilla version you want to download: " version
    url=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r --arg version "$version" '.versions[] | select(.id == $version) | .url')
    server_url=$(curl -s $url | jq -r '.downloads.server.url')
    echo "Downloading Vanilla version $version..."
    curl -o /home/minecraft/server/server.jar $server_url

    # Download eula.txt and server.properties
    wget -O /home/minecraft/server/eula.txt $EULA_URL
    wget -O /home/minecraft/server/server.properties $SERVER_PROPERTIES_URL
}

# Handle setup choices
if [ "$setup_choice" == "1" ]; then
    # New server setup
    echo "Select the Minecraft server provider:"
    echo "1) Paper"
    echo "2) Fabric"
    echo "3) Forge"
    echo "4) Vanilla"
    read -p "Enter your choice (1-4): " provider_choice

    # Download the selected server jar
    case $provider_choice in
        1)
            download_paper
            ;;
        2)
            download_fabric
            ;;
        3)
            download_forge
            ;;
        4)
            download_vanilla
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac
elif [ "$setup_choice" == "2" ]; then
    # Restore from pre-configured server zip file
    echo "Do you have a direct link for the .zip or a Dropbox link?"
    echo "1) Direct link"
    echo "2) Dropbox link"
    read -p "Enter your choice (1-2): " link_choice

    if [ "$link_choice" == "1" ]; then
        read -p "Enter the direct link for the server zip file: " DIRECT_LINK
        wget -O "$DOWNLOAD_DIR/mc-server-files.zip" "$DIRECT_LINK"
    elif [ "$link_choice" == "2" ]; then
        read -p "Enter your Dropbox shared link for the server zip file: " DROPBOX_URL
        DROPBOX_DIRECT_URL=${DROPBOX_URL/\?dl=0/\?dl=1}
        wget -O "$DOWNLOAD_DIR/mc-server-files.zip" "$DROPBOX_DIRECT_URL"
    else
        echo "Invalid link choice"
        exit 1
    fi

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
else
    echo "Invalid setup choice"
    exit 1
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
find "$DOWNLOAD_DIR"/* ! -name "$(basename "$0")" -exec rm -rf {} +

# Wait for one minute before reboot
echo "Waiting for one minute before reboot..."
sleep 60

# Initialize a reboot
reboot
