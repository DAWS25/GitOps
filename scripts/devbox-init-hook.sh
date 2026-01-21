#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

# Check dependencies versions
aws --version
cdk --version

# Check secrets
SECRETS_DIR="$DIR/../../GitOps-Secrets"
SECRETS_REPO="git@github.com:DAWS25/GitOps-Secrets.git"

if [ ! -d "$SECRETS_DIR" ]; then
  echo "Secrets directory not found: $SECRETS_DIR"
  chmod 600 /home/vscode/.ssh/id_rsa
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git clone "$SECRETS_REPO" "$SECRETS_DIR"
fi

#!
popd
echo "script [$0] completed"
