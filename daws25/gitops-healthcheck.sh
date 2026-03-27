#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TENANT_ID="${TENANT_ID:-gitops}"
VPC_STACK_NAME="${VPC_STACK_NAME:-${TENANT_ID}-gitops-vpc}"
EKS_STACK_NAME="${EKS_STACK_NAME:-${TENANT_ID}-gitops-eks}"
EXPECT_FARGATE_ONLY="${EXPECT_FARGATE_ONLY:-true}"
EKS_ADDONS="${EKS_ADDONS:-coredns metrics-server snapshot-controller}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

echo ""
echo "========================================"
echo "  GitOps Infrastructure Health Check"
echo "========================================"
echo ""

# Helper functions
print_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

check_stack_complete() {
    local stack_name="$1"
    local stack_label="$2"

    print_check "$stack_label stack existence"
    if aws cloudformation describe-stacks --stack-name "$stack_name" &>/dev/null; then
        local stack_status
        stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query "Stacks[0].StackStatus" \
            --output text)

        if [[ "$stack_status" == "CREATE_COMPLETE" || "$stack_status" == "UPDATE_COMPLETE" ]]; then
            print_pass "$stack_label stack exists and is in status: $stack_status"
            return 0
        fi

        print_fail "$stack_label stack status is: $stack_status"
        return 1
    fi

    print_fail "$stack_label stack does not exist"
    return 1
}

# ========================================
# VPC CHECKS
# ========================================
echo ""
echo -e "${BLUE}>>> VPC Stack Checks${NC}"
echo ""

check_stack_complete "$VPC_STACK_NAME" "VPC"

print_check "VPC Stack outputs"
if aws cloudformation describe-stacks --stack-name "$VPC_STACK_NAME" &>/dev/null; then
    VPC_ID=$(aws cloudformation describe-stacks \
        --stack-name "$VPC_STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" \
        --output text)
    
    PUBLIC_SUBNET=$(aws cloudformation describe-stacks \
        --stack-name "$VPC_STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetId'].OutputValue" \
        --output text)
    
    PRIVATE_SUBNET=$(aws cloudformation describe-stacks \
        --stack-name "$VPC_STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetId'].OutputValue" \
        --output text)
    
    if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
        print_pass "VPC ID retrieved: $VPC_ID"
        echo "  - Public Subnet: $PUBLIC_SUBNET"
        echo "  - Private Subnet: $PRIVATE_SUBNET"
    else
        print_fail "Could not retrieve VPC outputs"
    fi
else
    print_fail "VPC stack not accessible"
fi

print_check "VPC resource availability"
if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
    if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" &>/dev/null; then
        VPC_STATE=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query "Vpcs[0].State" --output text)
        if [[ "$VPC_STATE" == "available" ]]; then
            print_pass "VPC is available and responsive"
        else
            print_fail "VPC state is: $VPC_STATE"
        fi
    else
        print_fail "VPC is not accessible via EC2 API"
    fi
else
    print_warn "Skipping VPC resource check (VPC ID not available)"
fi

# ========================================
# EKS CHECKS
# ========================================
echo ""
echo -e "${BLUE}>>> EKS Stack Checks${NC}"
echo ""

check_stack_complete "$EKS_STACK_NAME" "EKS"

print_check "EKS Cluster name retrieval"
if aws cloudformation describe-stacks --stack-name "$EKS_STACK_NAME" &>/dev/null; then
    CLUSTER_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$EKS_STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='EksClusterName'].OutputValue" \
        --output text)
    
    if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "None" ]]; then
        print_pass "EKS Cluster name retrieved: $CLUSTER_NAME"
    else
        print_fail "Could not retrieve EKS cluster name from stack outputs"
    fi
else
    print_fail "EKS stack not accessible"
fi

print_check "EKS Cluster status"
if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "None" ]]; then
    if aws eks describe-cluster --name "$CLUSTER_NAME" &>/dev/null; then
        CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query "cluster.status" --output text)
        if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
            print_pass "EKS cluster is ACTIVE and responsive"
        else
            print_fail "EKS cluster status is: $CLUSTER_STATUS"
        fi
    else
        print_fail "EKS cluster is not accessible via EKS API"
    fi
else
    print_warn "Skipping EKS cluster status check (Cluster name not available)"
fi

print_check "EKS compute profile availability"
if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "None" ]]; then
    NODE_GROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query "nodegroups" --output text 2>/dev/null)

    FARGATE_PROFILES=$(aws eks list-fargate-profiles --cluster-name "$CLUSTER_NAME" --query "fargateProfileNames" --output text 2>/dev/null)

    if [[ -n "$NODE_GROUPS" && "$NODE_GROUPS" != "None" ]]; then
        NODE_GROUP_COUNT=$(echo "$NODE_GROUPS" | wc -w)
        print_pass "Found $NODE_GROUP_COUNT node group(s): $NODE_GROUPS"

        # Check each node group status
        for ng in $NODE_GROUPS; do
            NG_STATUS=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --query "nodegroup.status" --output text 2>/dev/null)
            if [[ "$NG_STATUS" == "ACTIVE" ]]; then
                echo "  - $ng: $NG_STATUS ✓"
            else
                echo "  - $ng: $NG_STATUS ✗"
            fi
        done
    elif [[ -n "$FARGATE_PROFILES" && "$FARGATE_PROFILES" != "None" ]]; then
        FARGATE_PROFILE_COUNT=$(echo "$FARGATE_PROFILES" | wc -w)
        print_pass "Found $FARGATE_PROFILE_COUNT Fargate profile(s): $FARGATE_PROFILES"
    elif [[ "$EXPECT_FARGATE_ONLY" == "true" ]]; then
        print_fail "No active Fargate profiles found for Fargate-only cluster"
    else
        print_fail "No node groups or Fargate profiles found"
    fi
else
    print_warn "Skipping compute profile check (Cluster name not available)"
fi

print_check "Native Amazon EKS add-ons"
if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "None" ]]; then
    for addon_name in $EKS_ADDONS; do
        ADDON_STATUS=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" --query "addon.status" --output text 2>/dev/null || true)
        if [[ "$ADDON_STATUS" == "ACTIVE" ]]; then
            print_pass "EKS add-on is ACTIVE: $addon_name"
        else
            print_fail "EKS add-on is not ACTIVE: $addon_name (${ADDON_STATUS:-missing})"
        fi
    done
else
    print_warn "Skipping add-on checks (Cluster name not available)"
fi

print_check "kubectl connectivity"
if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "None" ]]; then
    if command -v kubectl &>/dev/null; then
        # Update kubeconfig
        aws eks update-kubeconfig --name "$CLUSTER_NAME" 2>/dev/null || true
        
        # Try to get cluster info
        if kubectl cluster-info &>/dev/null; then
            print_pass "kubectl can connect to EKS cluster"
            
            # Additional context info
            NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
            echo "  - Nodes in cluster: $NODE_COUNT"
        else
            print_fail "kubectl cannot connect to EKS cluster"
        fi
    else
        print_warn "kubectl not installed, skipping connectivity check"
    fi
else
    print_warn "Skipping kubectl check (Cluster name not available)"
fi

# ========================================
# SUMMARY
# ========================================
echo ""
echo "========================================"
echo "  Health Check Summary"
echo "========================================"
echo -e "Passed: ${GREEN}${CHECKS_PASSED}${NC}"
echo -e "Failed: ${RED}${CHECKS_FAILED}${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! GitOps infrastructure is healthy.${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some checks failed. Please review the output above.${NC}"
    echo ""
    exit 1
fi
