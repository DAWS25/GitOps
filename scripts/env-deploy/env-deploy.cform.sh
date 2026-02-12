#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
##

STACK_NAME="codebuild-env-deploy"
TEMPLATE_FILE="$DIR/env-deploy.cform.yaml"

# Derive source repository URL from git remote
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [ -z "$REMOTE_URL" ]; then
    echo "Error: Could not determine git remote URL"
    exit 1
fi

# Convert SSH URL to HTTPS if needed
SOURCE_REPO=$(echo "$REMOTE_URL" | sed -E 's#git@github\.com:#https://github.com/#' | sed -E 's#\.git$##').git

# Get current branch
SOURCE_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

echo ""
echo "Deploying stack: $STACK_NAME"
echo "Template:        $TEMPLATE_FILE"
echo "Source Repo:     $SOURCE_REPO"
echo "Source Branch:   $SOURCE_BRANCH"
echo ""

aws cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameter-overrides \
        ProjectName="$STACK_NAME" \
        BuildSpec="scripts/env-deploy/env-deploy.buildspec.yaml" \
        ComputeType="BUILD_GENERAL1_LARGE" \
        SourceRepository="$SOURCE_REPO" \
        SourceBranch="$SOURCE_BRANCH" \
    --capabilities CAPABILITY_IAM \
    --no-fail-on-empty-changeset

# Retrieve outputs
PROJECT_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='CodeBuildProjectName'].OutputValue" \
    --output text)

PROJECT_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='CodeBuildProjectArn'].OutputValue" \
    --output text)

echo ""
echo "CodeBuild Project: $PROJECT_NAME"
echo "Project ARN:       $PROJECT_ARN"

##
popd
echo "script [$0] completed"
