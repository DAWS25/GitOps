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
INSTANCE_NAME="${TENANT_ID}-${ENV_ID}-k3s-argocd-$RANDOM"
STACK_NAME="${TENANT_ID}-${ENV_ID}-ec2-k3s-argocd"

if [ ! -f "$TEMPLATE_FILE" ]; then
	echo "Error: Template file not found at $TEMPLATE_FILE"
	exit 1
fi

echo "Deploying stack from: $TEMPLATE_FILE"

ARTIFACTS_BUCKET_NAME="$(aws cloudformation describe-stacks \
	--stack-name "${TENANT_ID}-${ENV_ID}-s3-artifacts" \
	--query "Stacks[0].Outputs[?OutputKey=='ArtifactsBucketName'].OutputValue | [0]" \
	--output text)"

echo "Using artifacts bucket: $ARTIFACTS_BUCKET_NAME"

aws cloudformation deploy \
	--template-file "$TEMPLATE_FILE" \
	--stack-name "$STACK_NAME" \
	--capabilities CAPABILITY_NAMED_IAM \
	--parameter-overrides TenantId="$TENANT_ID" EnvId="$ENV_ID" InstanceName="$INSTANCE_NAME" KeyName="$KEY_NAME" ArtifactsBucketName="$ARTIFACTS_BUCKET_NAME" \
	--tags TenantId="$TENANT_ID" EnvId="$ENV_ID" ServiceId="$SERVICE_ID" \
	--no-fail-on-empty-changeset

echo "Stack deployment completed successfully"

echo
echo "Stack outputs:"
aws cloudformation describe-stacks \
	--stack-name "$STACK_NAME" \
	--query "Stacks[0].Outputs[].{OutputKey:OutputKey,OutputValue:OutputValue}" \
	--output table

INSTANCE_ID="$(aws cloudformation describe-stack-resources \
	--stack-name "$STACK_NAME" \
	--logical-resource-id Instance \
	--query "StackResources[0].PhysicalResourceId" \
	--output text)"

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
	echo "Error: could not resolve EC2 instance id from stack resources"
	exit 1
fi

echo
echo "EC2 instance id: $INSTANCE_ID"
echo "Waiting for EC2 instance to reach running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

echo "Waiting for EC2 instance to pass status checks (healthy/ready)..."
for attempt in $(seq 1 40); do
	INSTANCE_STATUS="$(aws ec2 describe-instance-status \
		--instance-ids "$INSTANCE_ID" \
		--include-all-instances \
		--query 'InstanceStatuses[0].InstanceStatus.Status' \
		--output text)"
	SYSTEM_STATUS="$(aws ec2 describe-instance-status \
		--instance-ids "$INSTANCE_ID" \
		--include-all-instances \
		--query 'InstanceStatuses[0].SystemStatus.Status' \
		--output text)"
	INSTANCE_STATE="$(aws ec2 describe-instances \
		--instance-ids "$INSTANCE_ID" \
		--query 'Reservations[0].Instances[0].State.Name' \
		--output text)"
	echo "Attempt $attempt: state=$INSTANCE_STATE instance=$INSTANCE_STATUS system=$SYSTEM_STATUS"
	if [ "$INSTANCE_STATE" = "running" ] && [ "$INSTANCE_STATUS" = "ok" ] && [ "$SYSTEM_STATUS" = "ok" ]; then
		break
	fi
	if [ "$attempt" -eq 40 ]; then
		echo "Error: instance did not become healthy within the expected time"
		exit 1
	fi
	sleep 15
done
echo "EC2 instance is healthy and ready"

LOG_GROUP_NAME="$(aws cloudformation describe-stacks \
	--stack-name "$STACK_NAME" \
	--query "Stacks[0].Outputs[?OutputKey=='UserDataLogGroupName'].OutputValue | [0]" \
	--output text)"

LOG_STREAM_NAME="$(aws cloudformation describe-stacks \
	--stack-name "$STACK_NAME" \
	--query "Stacks[0].Outputs[?OutputKey=='UserDataLogStreamName'].OutputValue | [0]" \
	--output text)"

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
	LOG_STREAM_NAME="${INSTANCE_ID}/user-data"
fi

if [ -z "$LOG_GROUP_NAME" ] || [ "$LOG_GROUP_NAME" = "None" ]; then
	echo "Warning: UserDataLogGroupName output was not found"
else
	echo
	echo "CloudWatch user-data log group: $LOG_GROUP_NAME"
fi

if [ -z "$LOG_STREAM_NAME" ] || [ "$LOG_STREAM_NAME" = "None" ]; then
	echo "Warning: UserDataLogStreamName output was not found"
else
	echo "CloudWatch user-data log stream: $LOG_STREAM_NAME"
fi

if [ -n "$LOG_GROUP_NAME" ] && [ "$LOG_GROUP_NAME" != "None" ] && [ -n "$LOG_STREAM_NAME" ] && [ "$LOG_STREAM_NAME" != "None" ]; then
	echo
	"${SCRIPT_DIR}/ec2-k3s-argocd-logs.sh" "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
fi
