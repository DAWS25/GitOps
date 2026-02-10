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
export ENV_SECRETS_REPO="$REPO_DIR/../GitOps-Secrets"
export ENV_SECRETS_DIR="$ENV_SECRETS_REPO/env/$ENV_ID"
export MODULE_DIR="$REPO_DIR/modules/$ENV_PROJECT"

# If $ENV_SECRETS_DIR/.envrc exists, load it
echo "Loading environment variables from $ENV_SECRETS_DIR/.envrc"
if [ -f "$ENV_SECRETS_DIR/.envrc" ]; then
  source "$ENV_SECRETS_DIR/.envrc"
else
  echo "[WARNING] $ENV_SECRETS_DIR/.envrc not found!"
  sleep 5
fi

# check if the submodule in MOUDLE_DIR exists. if it is not initialized, initialize it. update to latest commit on origin main branch.
echo "[DEBUG] Checking submodule: $MODULE_DIR"
echo "[DEBUG] Current directory: $(pwd)"

# Configure git to use HTTPS with token if available, otherwise use HTTPS without token
if [ -n "$GITHUB_TOKEN" ]; then
    echo "[DEBUG] Configuring git to use GITHUB_TOKEN for authentication (token length: ${#GITHUB_TOKEN} chars)..."
    git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "git@github.com:"
    git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
    echo "[DEBUG] Git URL rewrite configuration applied"
else
    echo "[WARNING] No GITHUB_TOKEN found, using HTTPS without authentication..."
    echo "[WARNING] This may fail for private repositories!"
    git config --global url."https://github.com/".insteadOf "git@github.com:"
fi

echo "[DEBUG] Current git URL rewrites:"
git config --global --list | grep "url\." || echo "[DEBUG] No URL rewrites configured"

echo "[DEBUG] Checking if module directory exists: $MODULE_DIR"
ls -la "$MODULE_DIR" 2>/dev/null || echo "[DEBUG] Module directory does not exist yet"

pushd "$MODULE_DIR"
    if [ -f "./README.md" ]; then
        echo "[DEBUG] Submodule $MODULE_DIR found. Updating to latest commit on origin main branch..."
        echo "[DEBUG] Current git remote:"
        git remote -v
        echo "[DEBUG] Fetching from origin main..."
        git fetch origin main
        echo "[DEBUG] Checking out origin/main..."
        git checkout origin/main
        echo "[DEBUG] Current commit: $(git rev-parse HEAD)"
    else
        echo "[DEBUG] Submodule $MODULE_DIR not found or not initialized. Initializing submodule..."
        echo "[DEBUG] Running: git submodule update --init --recursive ."
        git submodule update --init --recursive .
        echo "[DEBUG] Submodule initialization complete"
    fi
    echo "[DEBUG] Submodule status:"
    git submodule status || echo "[DEBUG] No submodules in this directory"
popd

# Run deployment script
export TF_VAR_env_id="$ENV_ID"
source "$MODULE_DIR/scripts/env-deploy.sh"

#!
popd
echo "script [$0] completed"
