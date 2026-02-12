#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
##

PROJECT_NAME="codebuild-env-deploy"
LOG_GROUP="/aws/codebuild/${PROJECT_NAME}"

echo ""
echo "Starting CodeBuild project: $PROJECT_NAME"
echo ""

# Start the build
BUILD_JSON=$(aws codebuild start-build \
    --project-name "$PROJECT_NAME" \
    --environment-variables-override \
        "name=ENV_PROJECT,value=Presence,type=PLAINTEXT" \
        "name=ENV_GRADE,value=beta,type=PLAINTEXT")
BUILD_ID=$(echo "$BUILD_JSON" | grep -o '"id": "[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$BUILD_ID" ]; then
    echo "Error: Failed to start build"
    echo "$BUILD_JSON"
    exit 1
fi

echo "Build started: $BUILD_ID"
echo ""

# Extract the build-specific log stream name (build ID after the colon)
LOG_STREAM=$(echo "$BUILD_ID" | cut -d: -f2)

# Wait for CloudWatch log stream to become available
echo "Waiting for build logs..."
MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    STREAM_EXISTS=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --log-stream-name-prefix "$LOG_STREAM" \
        --query "logStreams[0].logStreamName" \
        --output text 2>/dev/null || echo "None")
    if [ "$STREAM_EXISTS" != "None" ] && [ -n "$STREAM_EXISTS" ]; then
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
    echo "  waiting... (${WAITED}s)"
done

if [ "$STREAM_EXISTS" = "None" ] || [ -z "$STREAM_EXISTS" ]; then
    echo "Warning: Log stream not available yet, falling back to polling build status"
fi

# Tail logs until build completes
echo ""
echo "=== Build Logs ==="
NEXT_TOKEN=""
while true; do
    # Check build status
    BUILD_STATUS=$(aws codebuild batch-get-builds \
        --ids "$BUILD_ID" \
        --query "builds[0].buildStatus" \
        --output text)

    # Fetch new log events
    if [ -n "$STREAM_EXISTS" ] && [ "$STREAM_EXISTS" != "None" ]; then
        if [ -z "$NEXT_TOKEN" ]; then
            LOG_OUTPUT=$(aws logs get-log-events \
                --log-group-name "$LOG_GROUP" \
                --log-stream-name "$LOG_STREAM" \
                --start-from-head \
                --output json 2>/dev/null || echo '{"events":[],"nextForwardToken":""}')
        else
            LOG_OUTPUT=$(aws logs get-log-events \
                --log-group-name "$LOG_GROUP" \
                --log-stream-name "$LOG_STREAM" \
                --next-token "$NEXT_TOKEN" \
                --start-from-head \
                --output json 2>/dev/null || echo '{"events":[],"nextForwardToken":""}')
        fi

        # Print log messages
        echo "$LOG_OUTPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for event in data.get('events', []):
    print(event.get('message', ''), end='')
" 2>/dev/null

        # Update token
        NEW_TOKEN=$(echo "$LOG_OUTPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('nextForwardToken', ''))
" 2>/dev/null)
        if [ -n "$NEW_TOKEN" ]; then
            NEXT_TOKEN="$NEW_TOKEN"
        fi
    fi

    # Exit if build is no longer in progress
    if [ "$BUILD_STATUS" != "IN_PROGRESS" ]; then
        sleep 3
        # Fetch remaining logs
        if [ -n "$STREAM_EXISTS" ] && [ "$STREAM_EXISTS" != "None" ] && [ -n "$NEXT_TOKEN" ]; then
            LOG_OUTPUT=$(aws logs get-log-events \
                --log-group-name "$LOG_GROUP" \
                --log-stream-name "$LOG_STREAM" \
                --next-token "$NEXT_TOKEN" \
                --start-from-head \
                --output json 2>/dev/null || echo '{"events":[]}')
            echo "$LOG_OUTPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for event in data.get('events', []):
    print(event.get('message', ''), end='')
" 2>/dev/null
        fi
        break
    fi

    sleep 3
done

echo ""
echo "=== Build Complete ==="
echo "Build ID:     $BUILD_ID"
echo "Build Status: $BUILD_STATUS"

if [ "$BUILD_STATUS" != "SUCCEEDED" ]; then
    echo ""
    echo "Build FAILED!"
    exit 1
fi

##
popd
echo "script [$0] completed"
