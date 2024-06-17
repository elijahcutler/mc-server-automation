# infrastructure

## Prerequisites

1. [Install Pulumi](https://www.pulumi.com/docs/get-started/install/)
1. [Configure Pulumi for Azure](https://www.pulumi.com/docs/intro/cloud-providers/azure/setup/)
1. [Configure Pulumi for Python](https://www.pulumi.com/docs/intro/languages/python/)

## Deploy and run

### 🪄 Auto-magic

1. Setup environment

   `./setup.sh`

1. Deploy stack

   `pulumi up`

1. Destroy stack

   `pulumi destroy`

### Manual

1. Create a stack

   ```bash
   $ pulumi stack init <stack_name>
   ```

1. Create a Python virtualenv, activate it, and install dependencies

   ```bash
   $ python -m venv .venv
   $ source .venv/bin/activate
   $ pip install -r requirements.txt
   ```

1. Generate an OpenSSH keypair

   ```bash
   $ ssh-keygen -t rsa -f rsa -b 4096 -m PEM
   ```

   This will output two files, `rsa` and `rsa.pub`, in the current directory. Be sure not to commit these files!

   We must configure our stack and make the public key and private available to the virtual machine. The private key is used for subsequent SCP and SSH steps that will configure our server after it is stood up.

   ```bash
   $ cat rsa.pub | pulumi config set publicKey --
   $ cat rsa | pulumi config set privateKey --secret --
   ```

   Notice that we've used `--secret` for `privateKey`. This ensures the private key is stored as an encrypted [Pulumi secret](https://www.pulumi.com/docs/intro/concepts/secrets/).

1. Set the required configuration. Check the Azure virtual machine [password requirements](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/faq#what-are-the-password-requirements-when-creating-a-vm) before creating a password.

   ```bash
   $ pulumi config set admin_password --secret <admin password>
   $ pulumi config set admin_username <admin username>
   $ pulumi config set azure-native:location eastus2 # any valid Azure region will do
   ```

   Note that `--secret` ensures your password is encrypted safely.

1. Run `pulumi up` to preview and deploy the changes:

   ```bash
   $ pulumi up
   ```

1. Get the IP address of the newly-created instance from the stack's outputs:

   ```bash
   $ pulumi stack output public_ip
   ```

1. Destroy the stack:

   ```bash
   pulumi destroy
   ```
