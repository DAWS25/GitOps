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

# Docker setup
if ! command -v docker &> /dev/null; then
    echo "docker could not be found, installing..."
    if [ "${PKG_MANAGER}" = "apt-get" ]; then
        echo "setting up Docker with apt-get"
        echo "setting up docker package repository..."
        sudo apt update
        sudo apt install ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources:
        sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
        Types: deb
        URIs: https://download.docker.com/linux/ubuntu
        Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
        Components: stable
        Signed-By: /etc/apt/keyrings/docker.asc
EOF

        sudo apt update
        echo "installing docker packages..."
        sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo groupadd docker
        sudo usermod -aG docker $USER
        newgrp docker
        docker run hello-world
    elif [ "${PKG_MANAGER}" = "yum" ]; then
        echo "Setting up Docker with yum"
    fi
    # Enable and start Docker (handle both systemd and service-based systems)
    if command -v systemctl &> /dev/null; then
        sudo systemctl enable --now docker
    else
        sudo service docker start || echo "Docker service start attempted"
    fi
fi

# Post-install: docker group and user access (per Docker official docs)
if ! getent group docker > /dev/null; then
    echo "Creating docker group..."
    sudo groupadd docker
fi
sudo usermod -aG docker ${USER}

# Ensure Docker daemon is running in non-systemd environments and fix socket permissions
if ! command -v systemctl &> /dev/null; then
    sudo service docker start || true
    sleep 2
    if [ -S /var/run/docker.sock ]; then
        sudo chmod 666 /var/run/docker.sock
    fi
fi

# DirEnv setup
if ! command -v direnv &> /dev/null
then
    echo "direnv could not be found, installing..."
    ${PKG_INSTALL_CMD} direnv
fi
touch .envrc
direnv allow .

# Info
echo "PWD: $(pwd)"

echo post-create.sh executed successfully.