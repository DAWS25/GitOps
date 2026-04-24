#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/s3-artifacts.cform.yaml"
TENANT_ID="GitOps"
ENV_ID="Main"
STACK_NAME="${TENANT_ID}-${ENV_ID}-s3-artifacts"
BUCKET_NAME="gitops-main-artifacts-20250326"

if [ ! -f "$TEMPLATE_FILE" ]; then
	echo "Error: Template file not found at $TEMPLATE_FILE"
	exit 1
fi

echo "Deploying stack from: $TEMPLATE_FILE"
echo "Bucket name: $BUCKET_NAME"

aws cloudformation deploy \
	--template-file "$TEMPLATE_FILE" \
	--stack-name "$STACK_NAME" \
	--parameter-overrides TenantId="$TENANT_ID" EnvId="$ENV_ID" BucketName="$BUCKET_NAME" \
	--tags TenantId="$TENANT_ID" EnvId="$ENV_ID" \
	--no-fail-on-empty-changeset

echo "Stack deployment completed successfully"

echo
echo "Stack outputs:"
aws cloudformation describe-stacks \
	--stack-name "$STACK_NAME" \
	--query "Stacks[0].Outputs[].{OutputKey:OutputKey,OutputValue:OutputValue}" \
	--output table
