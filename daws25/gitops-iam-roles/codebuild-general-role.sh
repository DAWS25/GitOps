#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
##

STACK_NAME="codebuild-general-role"
TEMPLATE_FILE="$DIR/codebuild-general-role.cform.yaml"

echo ""
echo "Deploying stack: $STACK_NAME"
echo "Template:        $TEMPLATE_FILE"
echo ""

aws cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

# Retrieve outputs
ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='CodeBuildServiceRoleArn'].OutputValue" \
    --output text)

ROLE_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='CodeBuildServiceRoleName'].OutputValue" \
    --output text)

echo ""
echo "Role ARN:  $ROLE_ARN"
echo "Role Name: $ROLE_NAME"

##
popd
echo "script [$0] completed"
