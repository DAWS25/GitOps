#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
##

STACK_NAME="gitops-eks"
TEMPLATE_FILE="$DIR/gitops-eks.cform.yaml"

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
CLUSTER_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='EksClusterName'].OutputValue" \
    --output text)

CLUSTER_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='EksClusterEndpoint'].OutputValue" \
    --output text)

CLUSTER_SG=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='EksClusterSecurityGroupId'].OutputValue" \
    --output text)

FARGATE_PROFILE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='FargateProfileArn'].OutputValue" \
    --output text)

echo ""
echo "EKS Cluster:         $CLUSTER_NAME"
echo "Endpoint:            $CLUSTER_ENDPOINT"
echo "Cluster SG:          $CLUSTER_SG"
echo "Fargate Profile ARN: $FARGATE_PROFILE_ARN"

# Update local kubeconfig — backup existing file with timestamp first
echo ""
echo "Updating kubeconfig for cluster: $CLUSTER_NAME"
KUBECONFIG_FILE="${KUBECONFIG:-$HOME/.kube/config}"
if [ -f "$KUBECONFIG_FILE" ]; then
  TS=$(date +%Y%m%d_%H%M%S)
  BACKUP="${KUBECONFIG_FILE}.bak.${TS}"
  echo "Backing up existing kubeconfig to: $BACKUP"
  cp "$KUBECONFIG_FILE" "$BACKUP"
fi
aws eks update-kubeconfig --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG_FILE"
echo "kubeconfig updated: $KUBECONFIG_FILE"

##
popd
echo "script [$0] completed"
