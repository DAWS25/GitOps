#!/bin/bash

# Script to fetch and print CloudWatch logs for ec2-k3s-argocd user-data
# Usage: ./ec2-k3s-argocd.logs.sh <log-group-name> <log-stream-name>

set -e

LOG_GROUP_NAME="${1:-}"
LOG_STREAM_NAME="${2:-}"

if [ -z "$LOG_GROUP_NAME" ]; then
	echo "Error: LOG_GROUP_NAME is required as the first argument"
	exit 1
fi

if [ -z "$LOG_STREAM_NAME" ]; then
	echo "Error: LOG_STREAM_NAME is required as the second argument"
	exit 1
fi

echo "Available log streams in group:"
aws logs describe-log-streams \
	--log-group-name "$LOG_GROUP_NAME" \
	--query "logStreams[].logStreamName" \
	--output table || true

echo
echo "=== CloudWatch Log Events (${LOG_STREAM_NAME}) ==="
aws logs get-log-events \
	--log-group-name "$LOG_GROUP_NAME" \
	--log-stream-name "$LOG_STREAM_NAME" \
	--start-from-head \
	--query "events[].message" \
	--output text || echo "(no events found)"
