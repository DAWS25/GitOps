#!/bin/bash
sudo chown -r $USER /nix
echo "PWD: $(pwd)"
direnv allow
echo post-create.sh executed successfully.