#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$DIR"
echo "script [$0] started at [$(pwd)]"
##

STACK_NAME="gitops-github-token"
TEMPLATE_FILE="$DIR/github-conn.cform.yaml"
AWS_REGION="${AWS_REGION:-us-east-1}"
PARAMETER_NAME="/gitops/github-token"

# Check if gh CLI is installed and authenticated
echo "=== Step 1: Verify GitHub CLI authentication ==="
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Install it with: sudo apt-get install gh (or brew install gh on macOS)"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "You are not authenticated with GitHub."
    echo "Running: gh auth login"
    gh auth login
fi

echo "✓ GitHub CLI authenticated"
gh auth status

# Get GitHub username for reference
GITHUB_USER=$(gh api user -q '.login')
echo "✓ GitHub user: $GITHUB_USER"

# Get GitHub token
echo ""
echo "=== Step 2: Get GitHub token ==="
GITHUB_TOKEN=$(gh auth token)
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: Could not retrieve GitHub token"
    exit 1
fi
echo "✓ GitHub token retrieved (${#GITHUB_TOKEN} chars)"

# Check if AWS CLI is configured
echo ""
echo "=== Step 3: Verify AWS CLI configuration ==="
if ! aws sts get-caller-identity &>/dev/null; then
    echo "Error: AWS CLI is not configured or credentials are invalid."
    echo "Run: aws configure"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "✓ AWS Account: $AWS_ACCOUNT_ID"
echo "✓ AWS Region: $AWS_REGION"

# Deploy CloudFormation stack
echo ""
echo "=== Step 4: Deploy CloudFormation stack ==="
echo "Stack Name: $STACK_NAME"
echo "Template: $TEMPLATE_FILE"

aws cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --region "$AWS_REGION" \
    --parameter-overrides "GitHubToken=$GITHUB_TOKEN" \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_IAM

echo "✓ CloudFormation stack deployed"

# Get the parameter name from stack outputs
echo ""
echo "=== Step 5: Verify parameter ==="
PARAM_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`GitHubTokenParameterName`].OutputValue' \
    --output text)

echo "Parameter Name: $PARAM_NAME"

# Verify the parameter exists
PARAM_VALUE=$(aws ssm get-parameter \
    --name "$PARAM_NAME" \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text)

if [ -n "$PARAM_VALUE" ]; then
    echo "✓ Parameter verified (${#PARAM_VALUE} chars)"
else
    echo "Error: Parameter not found or empty"
    exit 1
fi

echo ""
echo "=== Summary ==="
echo "Parameter Name: $PARAM_NAME"
echo "Stack Name: $STACK_NAME"
echo ""
echo "To use in CodeBuild environment variables:"
echo "  Environment:"
echo "    EnvironmentVariables:"
echo "      - Name: GITHUB_TOKEN"
echo "        Type: PARAMETER_STORE"
echo "        Value: $PARAM_NAME"
echo ""
echo "Or import in CloudFormation:"
echo "  - Name: GITHUB_TOKEN"
echo "    Type: PARAMETER_STORE"
echo "    Value: !ImportValue GitOps-GitHubTokenParameterName"

##
popd
echo "script [$0] completed"

