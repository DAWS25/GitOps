#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TENANT_ID="${TENANT_ID:-gitops}"
EKS_STACK_NAME="${EKS_STACK_NAME:-${TENANT_ID}-gitops-eks}"
VPC_STACK_NAME="${VPC_STACK_NAME:-${TENANT_ID}-gitops-vpc}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "========================================"
echo "  GitOps Infrastructure Destruction"
echo "========================================"
echo ""
echo -e "${RED}WARNING: This will destroy all GitOps resources including EKS cluster and VPC${NC}"
echo ""

echo ""
echo -e "${YELLOW}Starting resource destruction in 5 seconds... (Ctrl+C to cancel)${NC}"
sleep 5

# ========================================
# DESTROY EKS (must be first, depends on VPC)
# ========================================
echo ""
echo -e "${BLUE}[1/2] Destroying EKS resources...${NC}"
echo ""

if [ -f "$DIR/gitops-eks/gitops-eks.destroy.sh" ]; then
    STACK_NAME="$EKS_STACK_NAME" bash "$DIR/gitops-eks/gitops-eks.destroy.sh"
    EKS_DESTROY_STATUS=$?
    
    if [ $EKS_DESTROY_STATUS -ne 0 ]; then
        echo ""
        echo -e "${RED}ERROR: EKS destruction failed with status $EKS_DESTROY_STATUS${NC}"
        exit $EKS_DESTROY_STATUS
    fi
else
    echo -e "${YELLOW}WARNING: EKS destroy script not found at $DIR/gitops-eks/gitops-eks.destroy.sh${NC}"
    echo "Attempting to delete EKS stack directly..."
    aws cloudformation delete-stack --stack-name "$EKS_STACK_NAME" 2>/dev/null || true
    echo "Waiting for EKS stack deletion..."
    aws cloudformation wait stack-delete-complete --stack-name "$EKS_STACK_NAME" 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}✓ EKS destruction completed${NC}"
echo ""

# ========================================
# DESTROY VPC (must be last)
# ========================================
echo ""
echo -e "${BLUE}[2/2] Destroying VPC resources...${NC}"
echo ""

if [ -f "$DIR/gitops-vpc/gitops-vpc.destroy.sh" ]; then
    bash "$DIR/gitops-vpc/gitops-vpc.destroy.sh"
    VPC_DESTROY_STATUS=$?
    
    if [ $VPC_DESTROY_STATUS -ne 0 ]; then
        echo ""
        echo -e "${RED}ERROR: VPC destruction failed with status $VPC_DESTROY_STATUS${NC}"
        exit $VPC_DESTROY_STATUS
    fi
else
    echo -e "${YELLOW}WARNING: VPC destroy script not found at $DIR/gitops-vpc/gitops-vpc.destroy.sh${NC}"
    echo "Attempting to delete VPC stack directly..."
    aws cloudformation delete-stack --stack-name "$VPC_STACK_NAME" 2>/dev/null || true
    echo "Waiting for VPC stack deletion..."
    aws cloudformation wait stack-delete-complete --stack-name "$VPC_STACK_NAME" 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}✓ VPC destruction completed${NC}"
echo ""

# ========================================
# SUMMARY
# ========================================
echo ""
echo "========================================"
echo "  ✓ GitOps Infrastructure Destruction Complete"
echo "========================================"
echo ""
echo "All GitOps resources have been destroyed."
echo ""
