#!/bin/bash

# Nix fix
sudo chown -r $USER /nix

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

# Docker setup
if ! command -v docker &> /dev/null; then
    echo "docker could not be found, installing..."
    if [ "${PKG_MANAGER}" = "apt-get" ]; then
        ${PKG_INSTALL_CMD} ca-certificates curl gnupg lsb-release
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        . /etc/os-release
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        ${PKG_INSTALL_CMD} docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    elif [ "${PKG_MANAGER}" = "yum" ]; then
        ${PKG_INSTALL_CMD} yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        ${PKG_INSTALL_CMD} docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    sudo systemctl enable --now docker
fi

# Post-install: docker group and user access
if ! getent group docker > /dev/null; then
    echo "Creating docker group..."
    sudo groupadd docker
fi
sudo usermod -aG docker ${USER}

# DirEnv setup
if ! command -v direnv &> /dev/null
then
    echo "direnv could not be found, installing..."
    ${PKG_INSTALL_CMD} direnv
fi
direnv allow .

# Info
echo "PWD: $(pwd)"

echo post-create.sh executed successfully.