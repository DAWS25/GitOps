#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
##

STACK_NAME="gitops-github-connection"
TEMPLATE_FILE="$DIR/github-connection.cform.yaml"

# Derive GitHub owner from the git remote
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [ -z "$REMOTE_URL" ]; then
    echo "Error: Could not determine git remote URL"
    exit 1
fi

# Extract owner from SSH or HTTPS URL
# git@github.com:OWNER/REPO.git  or  https://github.com/OWNER/REPO.git
GITHUB_OWNER=$(echo "$REMOTE_URL" | sed -E 's#(git@|https://)github\.com[:/]##' | sed -E 's#/.*##')
GITHUB_REPO=$(echo "$REMOTE_URL" | sed -E 's#(git@|https://)github\.com[:/]##' | sed -E 's#\.git$##' | sed -E 's#^[^/]+/##')

echo "GitHub Owner: $GITHUB_OWNER"
echo "GitHub Repo:  $GITHUB_REPO"

# Derive connection name from stack name
CONNECTION_NAME="${STACK_NAME}"

echo ""
echo "Deploying stack: $STACK_NAME"
echo "Template:        $TEMPLATE_FILE"
echo "Connection:      $CONNECTION_NAME"
echo ""

aws cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameter-overrides \
        ConnectionName="$CONNECTION_NAME" \
    --capabilities CAPABILITY_IAM \
    --no-fail-on-empty-changeset

# Retrieve connection ARN and status
CONNECTION_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ConnectionArn'].OutputValue" \
    --output text)

CONNECTION_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ConnectionStatus'].OutputValue" \
    --output text)

echo ""
echo "Connection ARN:    $CONNECTION_ARN"
echo "Connection Status: $CONNECTION_STATUS"

if [ "$CONNECTION_STATUS" != "AVAILABLE" ]; then
    echo ""
    echo "NOTE: CodeConnection status is PENDING (requires browser-based OAuth)."
    echo "      Falling back to importing GitHub token as CodeBuild source credentials."
    echo ""
fi

# Import GitHub token as CodeBuild source credentials
# This allows CodeBuild to clone GitHub repos without the CodeConnection handshake
echo ""
echo "Importing GitHub credentials for CodeBuild..."

# Check if gh CLI is available and authenticated
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Install it with: sudo apt-get install gh  (or brew install gh on macOS)"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "You are not authenticated with GitHub CLI."
    echo "Running: gh auth login"
    echo ""
    gh auth login
fi

GITHUB_TOKEN=$(gh auth token)
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: Could not retrieve GitHub token from gh CLI"
    exit 1
fi
echo "GitHub token retrieved from gh CLI"

# Check for existing source credentials
EXISTING_CREDS=$(aws codebuild list-source-credentials \
    --query "sourceCredentialsInfos[?serverType=='GITHUB'].arn" \
    --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_CREDS" ] && [ "$EXISTING_CREDS" != "None" ]; then
    echo "Existing GitHub credentials found, replacing..."
    aws codebuild delete-source-credentials --arn "$EXISTING_CREDS" 2>/dev/null || true
fi

# Import the token as PERSONAL_ACCESS_TOKEN for CodeBuild
CRED_ARN=$(aws codebuild import-source-credentials \
    --server-type GITHUB \
    --auth-type PERSONAL_ACCESS_TOKEN \
    --token "$GITHUB_TOKEN" \
    --query "arn" \
    --output text)

echo ""
echo "GitHub source credentials imported successfully!"
echo "Credentials ARN: $CRED_ARN"
echo ""

# Verify
echo "Registered source credentials:"
aws codebuild list-source-credentials --output table

echo ""
echo "CodeBuild is now authorized to access GitHub repos for '${GITHUB_OWNER}'."

##
popd
echo "script [$0] completed"
