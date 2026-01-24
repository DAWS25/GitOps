#!/usr/bin/env bash
set -ex
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
#/

# Set environment ID and secrets directory
export ENV_PROJECT="OTO"
export ENV_GRADE="beta"
export ENV_SECRETS_REPO="$REPO_DIR/../GitOps-Secrets"

source "${REPO_DIR}/scripts/env-deploy.sh"

#/
popd
echo "script [$0] completed"
