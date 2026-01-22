#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

# Check if flutter is installed, install if not
if ! command -v flutter &> /dev/null; then
  # Install dependencies
  sudo apt-get update
  sudo apt-get install -y git curl clang cmake ninja-build pkg-config libgtk-3-dev

  # Clone Flutter SDK
  git clone https://github.com/flutter/flutter.git -b stable ~/flutter

  # Add Flutter to PATH
  export PATH="$PATH:~/flutter/bin"
  echo '' >> ~/.bashrc
  echo 'c' >> ~/.bashrc
  echo '' >> ~/.bashrc
  source ~/.bashrc

  # Verify installation
  flutter doctor

  # Accept Flutter licenses
  flutter doctor --android-licenses
fi

# Check dependencies versions
aws --version
cdk --version
flutter --version

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

git submodule update --init --recursive modules/

#!
popd
echo "script [$0] completed"
