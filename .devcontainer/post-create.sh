#!/bin/bash
sudo chown -r $USER /nix
echo 'eval \"$(direnv hook bash)\"' >> ~/.bashrc
eval "$(direnv hook bash)"
direnv allow .
echo post-create.sh executed successfully.