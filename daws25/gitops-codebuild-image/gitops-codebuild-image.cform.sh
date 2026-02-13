#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_NAME="gitops-codebuild-image"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "us-east-1")
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/gitops-ecr"

echo "## Login to ECR"
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

echo "## Build image"
docker build -t $REPO_NAME:latest -f "$DIR/Containerfile" "$DIR"

echo "## Tag and push to private ECR (gitops-ecr)"
docker tag $REPO_NAME:latest "$ECR_URI:$REPO_NAME"
docker push "$ECR_URI:$REPO_NAME"

echo "## Done: $ECR_URI:$REPO_NAME"
