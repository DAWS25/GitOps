#!/usr/bin/env bash
set -e
set -x # Enable debug mode, avoid commiting this line to prevent leaking variables to logs
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$DIR")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
#!

# Reusable deployment script
export ENV_ID="${ENV_PROJECT,,}-${ENV_GRADE,,}"
export ENV_SECRETS_DIR="$ENV_SECRETS_REPO/env/$ENV_ID"
export MODULE_DIR="$REPO_DIR/modules/$ENV_PROJECT"
export ENV_SECRETS_REPO="$REPO_DIR/../GitOps-Secrets"

# If $ENV_SECRETS_DIR/.envrc exists, load it
if [ -f "$ENV_SECRETS_DIR/.envrc" ]; then
  source "$ENV_SECRETS_DIR/.envrc"
else
  echo "[WARNING] $ENV_SECRETS_DIR/.envrc not found!"
fi

# Initialize git submodule modules/Presence
git submodule update --init "$MODULE_DIR"

# Run deployment script
source "$MODULE_DIR/scripts/env-deploy.sh"
#!
popd
echo "script [$0] completed"
