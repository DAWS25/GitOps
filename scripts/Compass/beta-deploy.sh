#!/usr/bin/env bash
set -ex
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
#/

# Set environment ID and secrets directory
export ENV_PROJECT="Compass"
export ENV_GRADE="beta"

source "${REPO_DIR}/scripts/env-deploy.sh"

#/
popd
echo "script [$0] completed"
