#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo ""
echo "========================================"
echo "  GitOps Infrastructure Deployment"
echo "========================================"
echo ""

# Deploy VPC
echo "[1/2] Deploying VPC..."
echo ""
bash "$DIR/gitops-vpc/gitops-vpc.sh"
VPC_DEPLOY_STATUS=$?

if [ $VPC_DEPLOY_STATUS -ne 0 ]; then
    echo "ERROR: VPC deployment failed with status $VPC_DEPLOY_STATUS"
    exit $VPC_DEPLOY_STATUS
fi

echo ""
echo "✓ VPC deployment completed successfully"
echo ""

# Deploy EKS
echo "[2/2] Deploying EKS..."
echo ""
bash "$DIR/gitops-eks/gitops-eks.sh"
EKS_DEPLOY_STATUS=$?

if [ $EKS_DEPLOY_STATUS -ne 0 ]; then
    echo "ERROR: EKS deployment failed with status $EKS_DEPLOY_STATUS"
    exit $EKS_DEPLOY_STATUS
fi

echo ""
echo "✓ EKS deployment completed successfully"
echo ""

# Run health check
echo "[3/3] Running health checks..."
echo ""
bash "$DIR/gitops-healthcheck.sh"
HEALTHCHECK_STATUS=$?

if [ $HEALTHCHECK_STATUS -ne 0 ]; then
    echo "ERROR: Health check failed with status $HEALTHCHECK_STATUS"
    exit $HEALTHCHECK_STATUS
fi

echo ""
echo "✓ Health checks completed successfully"
echo ""

echo "========================================"
echo "  ✓ GitOps Infrastructure Deployment Complete"
echo "========================================"
echo ""
