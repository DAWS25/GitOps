#!/usr/bin/env bash
set -ex

# Nix fix
sudo chown -R $USER /nix

# Package manager detection (apt or yum only)
if command -v apt-get &> /dev/null; then
    echo "Using apt-get as package manager."
    PKG_MANAGER="apt-get"
    PKG_UPDATE_CMD="sudo apt-get update"
    PKG_INSTALL_CMD="sudo apt-get install -y"
elif command -v yum &> /dev/null; then
    echo "Using yum as package manager."
    PKG_MANAGER="yum"
    PKG_UPDATE_CMD="sudo yum makecache"
    PKG_INSTALL_CMD="sudo yum install -y"
else
    echo "No supported package manager found (apt-get or yum)."
    exit 1
fi

${PKG_UPDATE_CMD}



# DirEnv setup
if ! command -v direnv &> /dev/null
then
    echo "direnv could not be found, installing..."
    ${PKG_INSTALL_CMD} direnv
fi
touch .envrc
direnv allow .
# 

# Info
echo "PWD: $(pwd)"

echo post-create.sh executed successfully.