#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

# Initialize git submodule modules/Presence
git submodule update --init modules/Presence

# Set environment ID
export ENV_ID="presence-beta"

# Run deployment script
./modules/Presence/deploy.sh

#!
popd
echo "script [$0] completed"
