#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/dns-delegation.cform.yaml"

STACK_NAME="${STACK_NAME:-presence-delegation}"
TENANT_ID="${TENANT_ID:-Perm}"
DOMAIN_NAME="${DOMAIN_NAME:-presence.daws25.com}"
PARENT_HOSTED_ZONE_ID="${PARENT_HOSTED_ZONE_ID:-Z01517313A2RZZSVFHBJN}"
PROJECT_ID="${PROJECT_ID:-Presence}"

export AWS_PAGER=""

if [ ! -f "$TEMPLATE_FILE" ]; then
	echo "Error: Template file not found at $TEMPLATE_FILE"
	exit 1
fi

echo "Deploying stack: $STACK_NAME"
echo "Template file: $TEMPLATE_FILE"

aws cloudformation deploy \
	--template-file "$TEMPLATE_FILE" \
	--stack-name "$STACK_NAME" \
	--parameter-overrides \
		TenantId="$TENANT_ID" \
		DomainName="$DOMAIN_NAME" \
		ParentHostedZoneId="$PARENT_HOSTED_ZONE_ID" \
	--tags \
		TenantId="$TENANT_ID" \
		ProjectId="$PROJECT_ID" \
	--no-fail-on-empty-changeset

echo
echo "Stack outputs:"
aws cloudformation describe-stacks \
	--stack-name "$STACK_NAME" \
	--query "Stacks[0].Outputs[].{OutputKey:OutputKey,OutputValue:OutputValue}" \
	--output table