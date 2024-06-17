#!/bin/bash

sudo apt-get -q update
apt-get upgrade -y
apt-get install zip unzip -y

curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 22-amzn
sudo mv ~/.sdkman/candidates/java/22-amzn /opt/java-22-amzn
sudo chmod -R 755 /opt/java-22-amzn
sudo ln -s /opt/java-22-amzn/bin/java /usr/bin/java
sudo ln -s /opt/java-22-amzn/bin/javac /usr/bin/javac

useradd -r -m -U -d /opt/minecraft -s /bin/bash minecraft

sudo -H -u minecraft mkdir -p /opt/minecraft/server
sudo -H -u minecraft wget https://api.papermc.io/v2/projects/paper/versions/1.20.6/builds/145/downloads/paper-1.20.6-145.jar -O /opt/minecraft/server/server.jar

# TODO: Pull files from .defaults

sudo -H -u minecraft touch /opt/minecraft/server/eula.txt
sudo -H -u minecraft echo 'eula=true' >> /opt/minecraft/server/eula.txt

touch /etc/systemd/system/minecraft.service
printf '[Unit]\nDescription=Minecraft Server\nAfter=network.target\n\n' >> /etc/systemd/system/minecraft.service
printf '[Service]\nUser=minecraft\nNice=1\nKillMode=none\n' >> /etc/systemd/system/minecraft.service
printf 'SuccessExitStatus=0 1\nProtectHome=true\n' >> /etc/systemd/system/minecraft.service
printf 'ProtectSystem=full\nPrivateDevices=true\nNoNewPrivileges=true\n' >> /etc/systemd/system/minecraft.service
printf 'WorkingDirectory=/opt/minecraft/server\n'  >> /etc/systemd/system/minecraft.service
printf 'ExecStart=/usr/bin/java -Xmx2048M -Xms512M -XX:+UseG1GC -jar server.jar nogui\n\n' >> /etc/systemd/system/minecraft.service
# printf 'ExecStop=/opt/minecraft/tools/mcrcon/mcrcon -H 127.0.0.1 -P 25575 -p strongpassword stop\n'  >> /etc/systemd/system/minecraft.service
printf '[Install]\nWantedBy=multi-user.target\n'  >> /etc/systemd/system/minecraft.service

systemctl daemon-reload
systemctl start minecraft
systemctl enable minecraft