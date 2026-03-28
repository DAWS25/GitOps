#!/bin/bash

# Script to fetch and print CloudWatch logs for ec2-k3s-argocd user-data
# Usage: ./ec2-k3s-argocd.logs.sh <log-group-name> <log-stream-name>

set -e

TENANT_ID="${TENANT_ID:-GitOps}"
ENV_ID="${ENV_ID:-Main}"
LOG_GROUP_NAME="${LOG_GROUP_NAME:-$TENANT_ID-$ENV_ID-logs}"
LOG_STREAM_NAME="${LOG_STREAM_NAME:-"general-log-stream"}"

if [ -z "$LOG_GROUP_NAME" ]; then
	echo "Error: LOG_GROUP_NAME is required"
	exit 1
fi

if [ -z "$LOG_STREAM_NAME" ]; then
	echo "Error: LOG_STREAM_NAME is required"
	exit 1
fi

echo "Available log streams in group:"
aws logs describe-log-streams \
	--log-group-name "$LOG_GROUP_NAME" \
	--query "logStreams[].logStreamName" \
	--output table || true

echo
echo "=== CloudWatch Log Events (${LOG_STREAM_NAME}) ==="
EVENTS_TEXT="$(aws logs get-log-events \
	--log-group-name "$LOG_GROUP_NAME" \
	--log-stream-name "$LOG_STREAM_NAME" \
	--start-from-head \
	--query "events[].message" \
	--output text 2>/dev/null || true)"

if [ -z "$EVENTS_TEXT" ] || [ "$EVENTS_TEXT" = "None" ]; then
	echo "(no events found)"
else
	# AWS text output returns list items tab-separated; convert to one log entry per line.
	printf "%s\n" "$EVENTS_TEXT" | tr '\t' '\n' | tr '\r' '\n'
fi
