#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
##

STACK_NAME="gitops-vpc"
TEMPLATE_FILE="$DIR/gitops-vpc.cform.yaml"

echo ""
echo "Deploying stack: $STACK_NAME"
echo "Template:        $TEMPLATE_FILE"
echo ""

aws cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --no-fail-on-empty-changeset

# Retrieve outputs
VPC_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" \
    --output text)

PUBLIC_SUBNET=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetId'].OutputValue" \
    --output text)

PRIVATE_SUBNET=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetId'].OutputValue" \
    --output text)

NAT_EIP=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='NatEipAddress'].OutputValue" \
    --output text)

echo ""
echo "VPC:            $VPC_ID"
echo "Public Subnet:  $PUBLIC_SUBNET"
echo "Private Subnet: $PRIVATE_SUBNET"
echo "NAT EIP:        $NAT_EIP"

##
popd
echo "script [$0] completed"
