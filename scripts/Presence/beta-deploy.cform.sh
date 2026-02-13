#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$DIR"
echo "script [$0] started at [$(pwd)]"
##

# Load environment variables
if [ -f "$REPO_DIR/.envrc" ]; then
    echo "Loading environment from $REPO_DIR/.envrc"
    source "$REPO_DIR/.envrc"
fi

PROJECT_NAME="presence-beta-deploy"
ROLE_STACK_NAME="${PROJECT_NAME}-role"
BUILD_STACK_NAME="${PROJECT_NAME}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Check if AWS CLI is configured
echo "=== Step 1: Verify AWS CLI configuration ==="
if ! aws sts get-caller-identity &>/dev/null; then
    echo "Error: AWS CLI is not configured or credentials are invalid."
    echo "Run: aws configure"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "✓ AWS Account: $AWS_ACCOUNT_ID"
echo "✓ AWS Region: $AWS_REGION"

# Deploy the IAM Role stack first
echo ""
echo "=== Step 2: Deploy IAM Role stack ==="
echo "Stack Name: $ROLE_STACK_NAME"
echo "Template: $DIR/beta-deploy-role.cform.yaml"

aws cloudformation deploy \
    --stack-name "$ROLE_STACK_NAME" \
    --template-file "$DIR/beta-deploy-role.cform.yaml" \
    --region "$AWS_REGION" \
    --parameter-overrides "ProjectName=$PROJECT_NAME" \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_NAMED_IAM

echo "✓ IAM Role stack deployed"

# Get role ARN for verification
ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$ROLE_STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CodeBuildServiceRoleArn`].OutputValue' \
    --output text)
echo "Role ARN: $ROLE_ARN"

# Deploy the CodeBuild project stack
echo ""
echo "=== Step 3: Deploy CodeBuild project stack ==="
echo "Stack Name: $BUILD_STACK_NAME"
echo "Template: $DIR/beta-deploy.cform.yaml"

aws cloudformation deploy \
    --stack-name "$BUILD_STACK_NAME" \
    --template-file "$DIR/beta-deploy.cform.yaml" \
    --region "$AWS_REGION" \
    --parameter-overrides "ProjectName=$PROJECT_NAME" \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_IAM

echo "✓ CodeBuild project stack deployed"

# Get project details
echo ""
echo "=== Step 4: Verify deployment ==="
PROJECT_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$BUILD_STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CodeBuildProjectArn`].OutputValue' \
    --output text)

echo "Project Name: $PROJECT_NAME"
echo "Project ARN: $PROJECT_ARN"

echo ""
echo "=== Summary ==="
echo "Role Stack: $ROLE_STACK_NAME"
echo "Role ARN: $ROLE_ARN"
echo "Build Stack: $BUILD_STACK_NAME"
echo "Project ARN: $PROJECT_ARN"
echo ""
echo "To start a build:"
echo "  aws codebuild start-build --project-name $PROJECT_NAME"

##
popd
echo "script [$0] completed"
