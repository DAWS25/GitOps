#!/usr/bin/env bash
set -ex
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
#!

# Initialize git submodule modules/Presence
git submodule update --init "$REPO_DIR/modules/Presence"

# Set environment ID and secrets directory
export ENV_ID="presence-beta"
export ENV_SECRETS_DIR="$REPO_DIR/../GitOps-Secrets/env/$ENV_ID"

# Run deployment script
source ./modules/Presence/scripts/env-deploy.sh

#!
popd
echo "script [$0] completed"
