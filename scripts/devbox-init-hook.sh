#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

if ! command -v flutter &> /dev/null; then
    echo "Flutter not found, installing..."
    sudo apt-get update
    sudo apt-get install -y curl git unzip xz-utils zip
    curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_latest.tar.xz
    tar xf flutter_linux_latest.tar.xz
    export PATH="$PATH:$HOME/flutter/bin"
    rm flutter_linux_latest.tar.xz
fi


# Check Dart version (require 3.12+)
DART_VERSION=$(flutter --version | grep -oE 'Dart [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')
REQUIRED_DART_MAJOR=3
REQUIRED_DART_MINOR=12
if [ -n "$DART_VERSION" ]; then
  DART_MAJOR=$(echo $DART_VERSION | cut -d. -f1)
  DART_MINOR=$(echo $DART_VERSION | cut -d. -f2)
  if [ "$DART_MAJOR" -lt "$REQUIRED_DART_MAJOR" ] || { [ "$DART_MAJOR" -eq "$REQUIRED_DART_MAJOR" ] && [ "$DART_MINOR" -lt "$REQUIRED_DART_MINOR" ]; }; then
    echo "Dart version $DART_VERSION found. Dart 3.12+ is required. Please update Flutter/Dart SDK."
    exit 1
  fi
else
  echo "Could not determine Dart version."
  exit 1
fi

# Accept Flutter licenses
yes | flutter doctor --android-licenses

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


#!
popd
echo "script [$0] completed"
