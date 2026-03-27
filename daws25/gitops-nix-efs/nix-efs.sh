#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
##

STACK_NAME="gitops-nix-efs"
TEMPLATE_FILE="$DIR/nix-efs.cform.yaml"

# Get gitops-vpc VPC and private subnet
VPC_ID=$(aws cloudformation describe-stacks \
    --stack-name gitops-vpc \
    --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" \
    --output text)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    echo "Error: gitops-vpc stack not found or has no VpcId output"
    exit 1
fi

SUBNET_IDS=$(aws cloudformation describe-stacks \
    --stack-name gitops-vpc \
    --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetIds'].OutputValue" \
    --output text)

if [ -z "$SUBNET_IDS" ]; then
    echo "Error: No private subnets found in gitops-vpc"
    exit 1
fi

echo ""
echo "Deploying stack: $STACK_NAME"
echo "Template:        $TEMPLATE_FILE"
echo "VPC:             $VPC_ID"
echo "Subnets:         $SUBNET_IDS"
echo ""

aws cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameter-overrides \
        VpcId="$VPC_ID" \
        SubnetIds="$SUBNET_IDS" \
    --no-fail-on-empty-changeset

# Retrieve outputs
FS_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='FileSystemId'].OutputValue" \
    --output text)

SG_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='SecurityGroupId'].OutputValue" \
    --output text)

AP_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='AccessPointId'].OutputValue" \
    --output text)

echo ""
echo "File System ID:   $FS_ID"
echo "Security Group:   $SG_ID"
echo "Access Point ID:  $AP_ID"

##
popd
echo "script [$0] completed"
