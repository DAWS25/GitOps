#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

TENANT_ID="${TENANT_ID:-GitOps}"
ENV_ID="${ENV_ID:-Main}"
ARTIFACTS_STACK_NAME="${ARTIFACTS_STACK_NAME:-${TENANT_ID}-${ENV_ID}-s3-artifacts}"

PRESENCE_DIR="${PRESENCE_DIR:-$REPO_DIR/modules/Presence}"
SAM_DIR="${SAM_DIR:-$PRESENCE_DIR/presence_sam}"
SAM_TEMPLATE="${SAM_TEMPLATE:-$SAM_DIR/template.yaml}"
PACKAGED_TEMPLATE="${PACKAGED_TEMPLATE:-$SAM_DIR/packaged-template.yaml}"

MAVEN_POM="${MAVEN_POM:-$SAM_DIR/pom.xml}"

export AWS_PAGER=""

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Error: required command '$1' not found"
		exit 1
	fi
}

require_cmd aws
require_cmd mvn
require_cmd sam

if [ ! -f "$SAM_TEMPLATE" ]; then
	echo "Error: SAM template not found at $SAM_TEMPLATE"
	exit 1
fi

if [ ! -f "$MAVEN_POM" ]; then
	echo "Error: Maven pom not found at $MAVEN_POM"
	echo "Set MAVEN_POM to the Presence SAM Maven module pom.xml path."
	exit 1
fi

echo "Resolving artifacts bucket from stack: $ARTIFACTS_STACK_NAME"
ARTIFACTS_BUCKET_NAME="$(aws cloudformation describe-stacks \
	--stack-name "$ARTIFACTS_STACK_NAME" \
	--query "Stacks[0].Outputs[?OutputKey=='ArtifactsBucketName'].OutputValue | [0]" \
	--output text 2>/dev/null || true)"

if [ -z "$ARTIFACTS_BUCKET_NAME" ] || [ "$ARTIFACTS_BUCKET_NAME" = "None" ]; then
	EXPORT_NAME="${TENANT_ID}-${ENV_ID}-ArtifactsBucketName"
	echo "Stack output not found, trying export: $EXPORT_NAME"
	ARTIFACTS_BUCKET_NAME="$(aws cloudformation list-exports \
		--query "Exports[?Name=='${EXPORT_NAME}'].Value | [0]" \
		--output text 2>/dev/null || true)"
fi

if [ -z "$ARTIFACTS_BUCKET_NAME" ] || [ "$ARTIFACTS_BUCKET_NAME" = "None" ]; then
	echo "Error: could not resolve artifacts bucket from stack/export"
	exit 1
fi

echo "Using artifacts bucket: $ARTIFACTS_BUCKET_NAME"

echo "Running Maven build"
mvn -f "$MAVEN_POM" -DskipTests package

echo "Packaging SAM template"
sam package \
	--template-file "$SAM_TEMPLATE" \
	--s3-bucket "$ARTIFACTS_BUCKET_NAME" \
	--output-template-file "$PACKAGED_TEMPLATE"

S3_KEY="presence/sam/packaged-template.yaml"
echo "Uploading packaged template to s3://$ARTIFACTS_BUCKET_NAME/$S3_KEY"
aws s3 cp "$PACKAGED_TEMPLATE" "s3://$ARTIFACTS_BUCKET_NAME/$S3_KEY"

echo "Done"
echo "Packaged template: $PACKAGED_TEMPLATE"
echo "S3 object: s3://$ARTIFACTS_BUCKET_NAME/$S3_KEY"
