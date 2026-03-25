#!/bin/bash

set -e

# Script to deploy ec2-k3s-argocd stack
# Usage: ./ec2-k3s-argocd.deploy.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/ec2-k3s.cform.yaml"
TENANT_ID="GitOps"
ENV_ID="Main"
SERVICE_ID="ArgoCD"
KEY_NAME="${TENANT_ID}-${ENV_ID}-gitops-keypair"
INSTANCE_NAME="${TENANT_ID}-${ENV_ID}-k3s-argocd"
STACK_NAME="${TENANT_ID}-${ENV_ID}-ec2-k3s-argocd"

if [ ! -f "$TEMPLATE_FILE" ]; then
	echo "Error: Template file not found at $TEMPLATE_FILE"
	exit 1
fi

echo "Deploying stack from: $TEMPLATE_FILE"

aws cloudformation deploy \
	--template-file "$TEMPLATE_FILE" \
	--stack-name "$STACK_NAME" \
	--capabilities CAPABILITY_NAMED_IAM \
	--parameter-overrides TenantId="$TENANT_ID" EnvId="$ENV_ID" InstanceName="$INSTANCE_NAME" KeyName="$KEY_NAME" \
	--tags TenantId="$TENANT_ID" EnvId="$ENV_ID" ServiceId="$SERVICE_ID" \
	--no-fail-on-empty-changeset

echo "Stack deployment completed successfully"
