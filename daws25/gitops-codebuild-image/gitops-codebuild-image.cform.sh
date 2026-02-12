#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STACK_NAME="gitops-codebuild-image"
REPO_NAME="gitops-codebuild-image"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "us-east-1")
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME"

echo "## Deploy ECR repository stack"
aws cloudformation deploy \
  --stack-name $STACK_NAME \
  --template-file "$DIR/$STACK_NAME.cform.yaml" \
  --no-fail-on-empty-changeset

echo "## Login to ECR"
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

echo "## Build image"
docker build -t $REPO_NAME:latest -f "$DIR/Containerfile" "$DIR"

echo "## Tag and push"
docker tag $REPO_NAME:latest "$ECR_URI:latest"
docker push "$ECR_URI:latest"

echo "## Done: $ECR_URI:latest"
