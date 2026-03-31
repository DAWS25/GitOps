#!/bin/bash

set -euo pipefail

# Script to fetch k3s kubeconfig from S3 and set it locally.
# Usage: ./ec2-k3s-argocd.kubeconfig.sh

TENANT_ID="${TENANT_ID:-GitOps}"
ENV_ID="${ENV_ID:-Main}"
ARTIFACTS_STACK_NAME="${ARTIFACTS_STACK_NAME:-${TENANT_ID}-${ENV_ID}-s3-artifacts}"
S3_KEY="${S3_KEY:-k3s/kubeconfig.yaml}"

# If KUBECONFIG has multiple entries, use the first one as destination.
DEFAULT_KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
LOCAL_KUBECONFIG="${LOCAL_KUBECONFIG:-${DEFAULT_KUBECONFIG%%:*}}"

export AWS_PAGER=""

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Error: required command '$1' not found"
		exit 1
	fi
}

require_cmd aws
require_cmd kubectl

ARTIFACTS_BUCKET_NAME="${ARTIFACTS_BUCKET_NAME:-}"
if [ -z "$ARTIFACTS_BUCKET_NAME" ]; then
	ARTIFACTS_BUCKET_NAME="$(aws cloudformation describe-stacks \
		--stack-name "$ARTIFACTS_STACK_NAME" \
		--query "Stacks[0].Outputs[?OutputKey=='ArtifactsBucketName'].OutputValue | [0]" \
		--output text 2>/dev/null || true)"
fi

if [ -z "$ARTIFACTS_BUCKET_NAME" ] || [ "$ARTIFACTS_BUCKET_NAME" = "None" ]; then
	echo "Error: artifacts bucket not found. Set ARTIFACTS_BUCKET_NAME or deploy stack '$ARTIFACTS_STACK_NAME'."
	exit 1
fi

SOURCE_URI="s3://${ARTIFACTS_BUCKET_NAME}/${S3_KEY}"
KUBE_DIR="$(dirname "$LOCAL_KUBECONFIG")"
mkdir -p "$KUBE_DIR"

if [ -f "$LOCAL_KUBECONFIG" ]; then
	TS="$(date +%Y%m%d%H%M%S)"
	BACKUP_FILE="${LOCAL_KUBECONFIG}.bak.${TS}"
	echo "Backing up existing kubeconfig to: $BACKUP_FILE"
	cp "$LOCAL_KUBECONFIG" "$BACKUP_FILE"
fi

echo "Downloading kubeconfig from: $SOURCE_URI"
if ! aws s3 cp "$SOURCE_URI" "$LOCAL_KUBECONFIG"; then
	echo "Error: failed to download kubeconfig from $SOURCE_URI"
	exit 1
fi

chmod 600 "$LOCAL_KUBECONFIG"
export KUBECONFIG="$LOCAL_KUBECONFIG"

echo "Verifying cluster connectivity using kubeconfig: $LOCAL_KUBECONFIG"
if kubectl version --request-timeout=10s --insecure-skip-tls-verify=true >/dev/null 2>&1 && kubectl get nodes --request-timeout=15s --insecure-skip-tls-verify=true >/dev/null 2>&1; then
	echo "Connection OK"
	exit 0
fi

echo "Error: kubeconfig fetched but cluster connection test failed"
exit 1