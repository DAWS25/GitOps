#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

# Flutter setup
# https://docs.flutter.dev/install/manual
FLUTTER_PACKAGE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.38.7-stable.tar.xz"
if ! command -v flutter &> /dev/null; then
    echo "Flutter not found, installing..."
    sudo apt-get update -y && sudo apt-get upgrade -y
    sudo apt-get install -y curl git unzip xz-utils zip libglu1-mesa
    curl -L -o /tmp/flutter_linux_latest.tar.xz "$FLUTTER_PACKAGE_URL"
    tar xf /tmp/flutter_linux_latest.tar.xz -C "$HOME"
    mkdir -p "$HOME/.local/bin"
    ln -s "$HOME/flutter/bin/flutter" "$HOME/.local/bin/flutter"
    ln -s "$HOME/flutter/bin/dart" "$HOME/.local/bin/dart"
    rm /tmp/flutter_linux_latest.tar.xz
    yes | flutter doctor --android-licenses
  fi


# Terraform setup
if ! command -v terraform &> /dev/null; then
    echo "Terraform not found, installing..."
    wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install terraform -y
fi


# Check dependencies versions
aws --version
cdk --version
flutter --version
dart --version
terraform version

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
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git clone "$SECRETS_REPO" "$SECRETS_DIR"
else
  echo "Secrets directory found: $SECRETS_DIR"
  git -C "$SECRETS_DIR" pull origin main
fi


#!
popd
echo "script [$0] completed"
