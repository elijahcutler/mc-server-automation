#!/bin/bash
pulumi stack init dev

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

ssh-keygen -t rsa -f rsa -b 4096 -m PEM

cat rsa.pub | pulumi config set publicKey --
cat rsa | pulumi config set privateKey --secret --

echo "Please enter a server password:"
read -s PASSWORD

pulumi config set admin_password --secret $PASSWORD
pulumi config set admin_username dev
pulumi config set azure-native:location eastus2

unset PASSWORD