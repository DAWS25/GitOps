#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
##

TENANT_ID="${TENANT_ID:-gitops}"
VPC_STACK_NAME="${VPC_STACK_NAME:-${TENANT_ID}-gitops-vpc}"
TEMPLATE_FILE="$DIR/gitops-vpc.cform.yaml"

echo ""
echo "Deploying stack: $VPC_STACK_NAME"
echo "Template:        $TEMPLATE_FILE"
echo ""

aws cloudformation deploy \
    --stack-name "$VPC_STACK_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameter-overrides \
        VpcName="$VPC_STACK_NAME" \
    --no-fail-on-empty-changeset

# Retrieve outputs
VPC_ID=$(aws cloudformation describe-stacks \
    --stack-name "$VPC_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" \
    --output text)

PUBLIC_SUBNET=$(aws cloudformation describe-stacks \
    --stack-name "$VPC_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetId'].OutputValue" \
    --output text)

PRIVATE_SUBNET_1=$(aws cloudformation describe-stacks \
    --stack-name "$VPC_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnet1Id'].OutputValue" \
    --output text)

PRIVATE_SUBNET_2=$(aws cloudformation describe-stacks \
    --stack-name "$VPC_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnet2Id'].OutputValue" \
    --output text)

PRIVATE_SUBNET_3=$(aws cloudformation describe-stacks \
    --stack-name "$VPC_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnet3Id'].OutputValue" \
    --output text)

PRIVATE_SUBNETS=$(aws cloudformation describe-stacks \
    --stack-name "$VPC_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetIds'].OutputValue" \
    --output text)

NAT_GW=$(aws cloudformation describe-stacks \
    --stack-name "$VPC_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='NatGatewayId'].OutputValue" \
    --output text)

NAT_EIP=$(aws cloudformation describe-stacks \
    --stack-name "$VPC_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='NatEipAddress'].OutputValue" \
    --output text)

IGW=$(aws cloudformation describe-stacks \
    --stack-name "$VPC_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='InternetGatewayId'].OutputValue" \
    --output text)

echo ""
echo "VPC:            $VPC_ID"
echo "Internet GW:    $IGW"
echo "Public Subnet:  $PUBLIC_SUBNET"
echo "Private Subnet1:$PRIVATE_SUBNET_1"
echo "Private Subnet2:$PRIVATE_SUBNET_2"
echo "Private Subnet3:$PRIVATE_SUBNET_3"
echo "Private Subnets:$PRIVATE_SUBNETS"
echo "NAT Gateway:    $NAT_GW"
echo "NAT EIP:        $NAT_EIP"

##
popd
echo "script [$0] completed"
