#!/usr/bin/env bash
set -ex
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
#!
# Reusable deployment script
export ENV_ID="${ENV_PROJECT,,}-${ENV_GRADE,,}"
export ENV_SECRETS_DIR="$ENV_SECRETS_REPO/env/$ENV_ID"
export MODULE_DIR="$REPO_DIR/modules/$ENV_PROJECT"

# Initialize git submodule modules/Presence
git submodule update --init "$MODULE_DIR"

# Run deployment script
source "$MODULE_DIR/scripts/env-deploy.sh"
#!
popd
echo "script [$0] completed"
