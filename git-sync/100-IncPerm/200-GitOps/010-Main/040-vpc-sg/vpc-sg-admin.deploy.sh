#!/bin/bash

set -e

# Script to deploy vpc-sg-admin stack
# Usage: ./vpc-sg-admin.deploy.sh [admin_ingress_cidr]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/vpc-sg-admin.cform.yaml"
TENANT_ID="GitOps"
ENV_ID="Main"
SERVICE_ID="VpcSg"
STACK_NAME="${TENANT_ID}-${ENV_ID}-vpc-sg-admin"
ADMIN_INGRESS_CIDR="${1:-0.0.0.0/0}"

if [ ! -f "$TEMPLATE_FILE" ]; then
	echo "Error: Template file not found at $TEMPLATE_FILE"
	exit 1
fi

echo "Deploying stack from: $TEMPLATE_FILE"
echo "Admin ingress CIDR: $ADMIN_INGRESS_CIDR"

aws cloudformation deploy \
	--template-file "$TEMPLATE_FILE" \
	--stack-name "$STACK_NAME" \
	--parameter-overrides TenantId="$TENANT_ID" EnvId="$ENV_ID" AdminIngressCidr="$ADMIN_INGRESS_CIDR" \
	--tags TenantId="$TENANT_ID" EnvId="$ENV_ID" ServiceId="$SERVICE_ID" \
	--no-fail-on-empty-changeset

echo "Stack deployment completed successfully"

echo
echo "Stack outputs:"
aws cloudformation describe-stacks \
	--stack-name "$STACK_NAME" \
	--query "Stacks[0].Outputs[].{OutputKey:OutputKey,OutputValue:OutputValue}" \
	--output table
