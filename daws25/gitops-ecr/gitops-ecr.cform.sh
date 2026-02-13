#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STACK_NAME="gitops-ecr"

echo "## Deploy private ECR repository stack"
aws cloudformation deploy \
  --stack-name $STACK_NAME \
  --template-file "$DIR/$STACK_NAME.cform.yaml" \
  --no-fail-on-empty-changeset

echo "## Stack outputs:"
aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" \
  --output table
