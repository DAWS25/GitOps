#!/bin/bash

set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

# SSH key check
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [ -f "$SSH_KEY_PATH" ]; then
  echo "Using existing SSH key at $SSH_KEY_PATH"
  chmod 600 "$SSH_KEY_PATH"
fi

# for each git submodule module under modules/*, initialize git submodule if needed and update (pull latest changes) from origin main branch
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
for MODULE_DIR in modules/*/; do
    pushd "$MODULE_DIR"
    if [ -f "./README.md" ]; then
        echo "Submodule $MODULE_DIR found. Updating to latest commit on origin main branch..."
        git fetch origin main
        git checkout origin/main
    else
        echo "Submodule $MODULE_DIR not found or not initialized. Initializing submodule..."
        git submodule update --init --recursive .
    fi
    popd
done
#!
popd
echo "script [$0] completed"
