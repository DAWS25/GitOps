#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

# Detect if the system is Ubuntu/Debian based or Red Hat / AMZN based, using the package manager available.
# Install common dependencies
if command -v apt-get &> /dev/null; then
    echo "Detected apt-get package manager. Installing common dependencies..."
    sudo apt-get update -y
    
    # Setup HashiCorp repository
    if [ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
        echo "Setting up HashiCorp repository..."
        wget -q -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null || true
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
        sudo apt-get update -y >/dev/null 2>&1
    else
        echo "HashiCorp repository already configured"
    fi
    
    # Install core dependencies if not already present
    if ! command -v terraform &> /dev/null; then
        echo "Installing terraform..."
        sudo apt-get install -y terraform
    else
        echo "terraform already installed"
    fi
    
    # Install system packages
    PACKAGES_TO_INSTALL=""
    for pkg in git curl unzip wget xz-utils zip libglu1-mesa; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $pkg"
        fi
    done
    
    if [ ! -z "$PACKAGES_TO_INSTALL" ]; then
        echo "Installing packages:$PACKAGES_TO_INSTALL"
        sudo apt-get install -y $PACKAGES_TO_INSTALL
    else
        echo "All required packages already installed"
    fi
elif command -v yum &> /dev/null; then
    echo "Detected yum package manager. Installing common dependencies..."
    sudo yum update -y
    
    # Install core dependencies if not already present
    if ! command -v terraform &> /dev/null; then
        echo "Installing terraform..."
        sudo yum install -y terraform
    else
        echo "terraform already installed"
    fi
    
    # Install system packages
    PACKAGES_TO_INSTALL=""
    for pkg in git curl unzip wget zip mesa-libGLU; do
        if ! rpm -q "$pkg" &>/dev/null; then
            PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $pkg"
        fi
    done
    
    if [ ! -z "$PACKAGES_TO_INSTALL" ]; then
        echo "Installing packages:$PACKAGES_TO_INSTALL"
        sudo yum install -y $PACKAGES_TO_INSTALL
    else
        echo "All required packages already installed"
    fi
else
    echo "No supported package manager found (apt-get or yum)"
fi

# Flutter setup
# https://docs.flutter.dev/install/manual
FLUTTER_PACKAGE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.38.7-stable.tar.xz"
if ! command -v flutter &> /dev/null; then
    echo "Flutter not found, installing..."
    curl -s -L -o /tmp/flutter_linux_latest.tar.xz "$FLUTTER_PACKAGE_URL"
    tar xf /tmp/flutter_linux_latest.tar.xz -C "$HOME"
    mkdir -p "$HOME/.local/bin"
    ln -sf "$HOME/flutter/bin/flutter" "$HOME/.local/bin/flutter"
    ln -sf "$HOME/flutter/bin/dart" "$HOME/.local/bin/dart"
    rm /tmp/flutter_linux_latest.tar.xz
    yes | flutter doctor --android-licenses >/dev/null 2>&1 || true
  fi



# SAM Setup
SAM_URL="https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-x86_64.zip"
if ! command -v sam &> /dev/null
then
    echo "AWS SAM CLI not found, installing..."
    wget -q $SAM_URL -O "/tmp/aws-sam-cli-linux-x86_64.zip"
    unzip -q /tmp/aws-sam-cli-linux-x86_64.zip -d /tmp/sam-installation
    sudo -n bash -c "cd /tmp/sam-installation && ./install -i /usr/local/aws-cli -b /usr/local/bin" 2>/dev/null || sudo /tmp/sam-installation/install
    rm -rf /tmp/sam-installation /tmp/aws-sam-cli-linux-x86_64.zip
fi

# Node setup
NVM_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh"
if ! command -v node &> /dev/null; then
   # Setup nodejs using nvm
  echo "Node.js not found, installing..."
  curl -s -o- $NVM_URL | bash >/dev/null 2>&1
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  nvm install --lts >/dev/null 2>&1
  ln -sf "$(which node)" "$HOME/.local/bin/node"
fi


# Check dependencies versions
echo "Checking installed tools..."
command -v aws &>/dev/null && aws --version || echo "aws CLI not found"
command -v cdk &>/dev/null && cdk --version || echo "AWS CDK not found"
command -v sam &>/dev/null && sam --version || echo "AWS SAM not found"
command -v terraform &>/dev/null && terraform version || echo "Terraform not found"
command -v flutter &>/dev/null && flutter --version || echo "Flutter not found"
command -v dart &>/dev/null && dart --version || echo "Dart not found"
command -v java &>/dev/null && java --version || echo "Java not found"

# SSH key setup
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [ -f "$SSH_KEY_PATH" ]; then
  echo "Using existing SSH key at $SSH_KEY_PATH"
  chmod 600 "$SSH_KEY_PATH"
fi

# Check secrets
SECRETS_DIR="$DIR/../../GitOps-Secrets"
SECRETS_REPO="git@github.com:DAWS25/GitOps-Secrets.git"

if [ ! -d "$SECRETS_DIR" ]; then
  echo "Secrets directory not found: $SECRETS_DIR"
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o BatchMode=yes" git clone "$SECRETS_REPO" "$SECRETS_DIR" 2>/dev/null || echo "[WARNING] Failed to clone secrets repository"
else
  echo "Secrets directory found: $SECRETS_DIR"
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o BatchMode=yes" git -C "$SECRETS_DIR" pull origin main 2>/dev/null || echo "[WARNING] Failed to pull secrets repository"
fi


#!
popd
echo "script [$0] completed"
