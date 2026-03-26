#!/bin/bash

set -e

# Script to deploy s3-artifacts stack
# Usage: ./s3-artifacts.deploy.sh <bucket-name>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/s3-artifacts.cform.yaml"
TENANT_ID="GitOps"
ENV_ID="Main"
SERVICE_ID="S3Artifacts"
STACK_NAME="${TENANT_ID}-${ENV_ID}-s3-artifacts"
BUCKET_NAME="${1:-}"

if [ ! -f "$TEMPLATE_FILE" ]; then
	echo "Error: Template file not found at $TEMPLATE_FILE"
	exit 1
fi

if [ -z "$BUCKET_NAME" ]; then
	echo "Error: BucketName is required as the first argument (must be globally unique and lowercase)"
	echo "Usage: $0 <bucket-name>"
	exit 1
fi

echo "Deploying stack from: $TEMPLATE_FILE"
echo "Bucket name: $BUCKET_NAME"

aws cloudformation deploy \
	--template-file "$TEMPLATE_FILE" \
	--stack-name "$STACK_NAME" \
	--parameter-overrides TenantId="$TENANT_ID" EnvId="$ENV_ID" BucketName="$BUCKET_NAME" \
	--tags TenantId="$TENANT_ID" EnvId="$ENV_ID" ServiceId="$SERVICE_ID" \
	--no-fail-on-empty-changeset

echo "Stack deployment completed successfully"

echo
echo "Stack outputs:"
aws cloudformation describe-stacks \
	--stack-name "$STACK_NAME" \
	--query "Stacks[0].Outputs[].{OutputKey:OutputKey,OutputValue:OutputValue}" \
	--output table
