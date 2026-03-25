#!/bin/bash

set -e

# Script to deploy .stack.yaml file
# Usage: ./ec2-gitops-keypair.stack.deploy.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_FILE="${SCRIPT_DIR}/ec2-gitops-keypair.stack.yaml"

if [ ! -f "$STACK_FILE" ]; then
    echo "Error: Stack file not found at $STACK_FILE"
    exit 1
fi

echo "Deploying stack from: $STACK_FILE"

# Deploy using AWS CloudFormation
aws cloudformation deploy \
    --template-file "$STACK_FILE" \
    --stack-name ec2-gitops-keypair \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

echo "Stack deployment completed successfully"