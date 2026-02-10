#!/usr/bin/env bash
set -e

echo "GitHub Token Generation Script"
echo "=============================="
echo ""

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Install it with: sudo apt-get install gh  (or brew install gh on macOS)"
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &>/dev/null; then
    echo "You are not authenticated with GitHub."
    echo "Running: gh auth login"
    echo ""
    gh auth login
fi

echo ""
echo "Generating fine-grained personal access token..."
echo "This token will have read-only access to your repositories."
echo ""

# Generate token using gh cli
TOKEN=$(gh auth token)

if [ -z "$TOKEN" ]; then
    echo "Error: Could not retrieve token"
    exit 1
fi

echo ""
echo "✓ Token generated successfully!"
echo ""
echo "Token: $TOKEN"
echo ""
echo "Next steps:"
echo "1. Copy the token above"
echo "2. In AWS CodeBuild project settings:"
echo "   - Go to Environment → Additional configuration"
echo "   - Add environment variable:"
echo "     Name: GITHUB_TOKEN"
echo "     Value: (paste your token)"
echo ""
echo "3. Update your buildspec.yml pre_build phase:"
echo '   - git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "git@github.com:"'
echo '   - git submodule update --init --recursive'
echo ""
