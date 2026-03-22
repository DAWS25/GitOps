#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$DIR")")"
pushd "$REPO_DIR"
echo "script [$0] started at [$(pwd)]"
##

TENANT_ID="${TENANT_ID:-gitops}"
EKS_STACK_NAME="${EKS_STACK_NAME:-${TENANT_ID}-eks}"
TEMPLATE_FILE="$DIR/gitops-eks.cform.yaml"
CLUSTER_NAME_PARAM="${CLUSTER_NAME_PARAM:-gitops-eks}"
CLUSTER_VERSION="${CLUSTER_VERSION:-1.35}"
FARGATE_PROFILE_NAME="${FARGATE_PROFILE_NAME:-gitops-fargate-profile-v3}"
CFN_CAPABILITIES="${CFN_CAPABILITIES:-CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND}"

echo ""
echo "Deploying stack: $EKS_STACK_NAME"
echo "Template:        $TEMPLATE_FILE"
echo "TenantId:        $TENANT_ID"
echo "ClusterName:     $CLUSTER_NAME_PARAM"
echo "ClusterVersion:  $CLUSTER_VERSION"
echo "FargateProfile:  $FARGATE_PROFILE_NAME"
echo ""

if aws cloudformation describe-stacks --stack-name "$EKS_STACK_NAME" >/dev/null 2>&1; then
    STACK_EXISTS=true
else
    STACK_EXISTS=false
fi

if [ "$STACK_EXISTS" = "false" ]; then
    echo "First deployment for $EKS_STACK_NAME detected; bootstrapping cluster before managed add-ons..."
    aws cloudformation deploy \
        --stack-name "$EKS_STACK_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameter-overrides \
            TenantId="$TENANT_ID" \
            ClusterName="$CLUSTER_NAME_PARAM" \
            ClusterVersion="$CLUSTER_VERSION" \
            FargateProfileName="$FARGATE_PROFILE_NAME" \
            EnableManagedAddons="false" \
        --capabilities ${CFN_CAPABILITIES} \
        --no-fail-on-empty-changeset
fi

echo "Applying declarative native EKS add-ons through CloudFormation..."
aws cloudformation deploy \
    --stack-name "$EKS_STACK_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameter-overrides \
        TenantId="$TENANT_ID" \
        ClusterName="$CLUSTER_NAME_PARAM" \
        ClusterVersion="$CLUSTER_VERSION" \
        FargateProfileName="$FARGATE_PROFILE_NAME" \
        EnableManagedAddons="true" \
    --capabilities ${CFN_CAPABILITIES} \
    --no-fail-on-empty-changeset

# Retrieve outputs
CLUSTER_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$EKS_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='EksClusterName'].OutputValue" \
    --output text)

CLUSTER_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "$EKS_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='EksClusterEndpoint'].OutputValue" \
    --output text)

CLUSTER_SG=$(aws cloudformation describe-stacks \
    --stack-name "$EKS_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='EksClusterSecurityGroupId'].OutputValue" \
    --output text)

FARGATE_PROFILE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$EKS_STACK_NAME" \
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

echo ""
echo "Native EKS add-ons are managed declaratively by CloudFormation."

##
popd
echo "script [$0] completed"
