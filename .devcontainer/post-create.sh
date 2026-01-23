#!/bin/bash

# Nix fix
sudo chown -r $USER /nix

# DirEnv installation check
if ! command -v direnv &> /dev/null
then
    echo "direnv could not be found, installing..."
    sudo apt-get update
    sudo apt-get install -y direnv
else
    direnv allow .
fi

# Info
echo "PWD: $(pwd)"

echo post-create.sh executed successfully.