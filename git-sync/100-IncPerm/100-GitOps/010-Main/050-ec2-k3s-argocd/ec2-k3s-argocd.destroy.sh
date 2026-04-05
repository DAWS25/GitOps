#!/bin/bash

set -e

# Script to destroy ec2-k3s-argocd stack
# Usage: ./ec2-k3s-argocd.destroy.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/ec2-k3s.cform.yaml"
TENANT_ID="GitOps"
ENV_ID="Main"
STACK_NAME="${TENANT_ID}-${ENV_ID}-ec2-k3s-argocd"

if [ ! -f "$TEMPLATE_FILE" ]; then
	echo "Error: Template file not found at $TEMPLATE_FILE"
	exit 1
fi

echo "Deleting stack: $STACK_NAME"

aws cloudformation delete-stack \
	--stack-name "$STACK_NAME"

aws cloudformation wait stack-delete-complete \
	--stack-name "$STACK_NAME"

echo "Stack deletion completed successfully"
