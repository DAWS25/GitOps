#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
##

STACK_NAME="nix-efs"
TEMPLATE_FILE="$DIR/nix-efs.cform.yaml"

# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" --output text)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    echo "Error: No default VPC found"
    exit 1
fi

# Get first 3 subnets from the VPC (one per AZ)
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[*].SubnetId" --output text | tr '\t' ',' | cut -d, -f1-3)

if [ -z "$SUBNET_IDS" ]; then
    echo "Error: No subnets found in VPC $VPC_ID"
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
