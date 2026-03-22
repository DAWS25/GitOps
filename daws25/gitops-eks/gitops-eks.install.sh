#!/usr/bin/env bash
set -euo pipefail

# Installs AWS Load Balancer Controller if it is not already present,
# then creates or updates a public ALB ingress for Argo CD.

CLUSTER_NAME="${EKS_CLUSTER:-gitops-eks}"
REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}}"
NAMESPACE="${AWS_LBC_NAMESPACE:-kube-system}"
RELEASE_NAME="${AWS_LBC_RELEASE_NAME:-aws-load-balancer-controller}"
CHART_VERSION="${AWS_LBC_CHART_VERSION:-1.13.0}"
TIMEOUT="${AWS_LBC_TIMEOUT:-10m}"
SERVICE_ACCOUNT_NAME="${AWS_LBC_SERVICE_ACCOUNT_NAME:-aws-load-balancer-controller}"
SERVICE_ACCOUNT_ROLE_ARN="${AWS_LBC_ROLE_ARN:-}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_SERVICE_NAME="${ARGOCD_SERVICE_NAME:-argocd-server}"
ARGOCD_SERVICE_PORT="${ARGOCD_SERVICE_PORT:-80}"
ARGOCD_INGRESS_NAME="${ARGOCD_INGRESS_NAME:-argocd-public}"
ARGOCD_HOSTNAME="${ARGOCD_HOSTNAME:-}"
ARGOCD_ACM_CERTIFICATE_ARN="${ARGOCD_ACM_CERTIFICATE_ARN:-}"
ARGOCD_ALB_SCHEME="${ARGOCD_ALB_SCHEME:-internet-facing}"
ARGOCD_TARGET_TYPE="${ARGOCD_TARGET_TYPE:-ip}"

require_cmd() {
	local cmd="$1"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "ERROR: required command not found: $cmd" >&2
		exit 1
	fi
}

log() {
	printf "\n==> %s\n" "$1"
}

controller_exists() {
	kubectl -n "$NAMESPACE" get deployment "$RELEASE_NAME" >/dev/null 2>&1
}

install_controller() {
	if controller_exists; then
		log "AWS Load Balancer Controller already installed in namespace ${NAMESPACE}; skipping install"
		kubectl -n "$NAMESPACE" get deployment "$RELEASE_NAME"
		return
	fi

	log "Installing AWS Load Balancer Controller"
	helm repo add eks https://aws.github.io/eks-charts >/dev/null
	helm repo update >/dev/null

	helm_args=(
		upgrade --install "$RELEASE_NAME" eks/aws-load-balancer-controller
		--namespace "$NAMESPACE"
		--create-namespace
		--version "$CHART_VERSION"
		--set clusterName="$CLUSTER_NAME"
		--set region="$REGION"
		--set serviceAccount.create=true
		--set serviceAccount.name="$SERVICE_ACCOUNT_NAME"
	)

	if [[ -n "$SERVICE_ACCOUNT_ROLE_ARN" ]]; then
		helm_args+=(--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$SERVICE_ACCOUNT_ROLE_ARN")
	else
		echo "WARNING: AWS_LBC_ROLE_ARN is empty. Controller may not have required AWS IAM permissions."
	fi

	helm "${helm_args[@]}"

	log "Waiting for deployment rollout"
	kubectl -n "$NAMESPACE" rollout status deployment/"$RELEASE_NAME" --timeout="$TIMEOUT"

	log "AWS Load Balancer Controller installation complete"
	kubectl -n "$NAMESPACE" get deployment "$RELEASE_NAME"
}

create_argocd_ingress() {
	if [[ -z "$ARGOCD_HOSTNAME" || -z "$ARGOCD_ACM_CERTIFICATE_ARN" ]]; then
		echo "WARNING: skipping Argo CD ingress creation because ARGOCD_HOSTNAME or ARGOCD_ACM_CERTIFICATE_ARN is not set."
		return
	fi

	if ! kubectl -n "$ARGOCD_NAMESPACE" get service "$ARGOCD_SERVICE_NAME" >/dev/null 2>&1; then
		echo "ERROR: Argo CD service ${ARGOCD_NAMESPACE}/${ARGOCD_SERVICE_NAME} was not found." >&2
		exit 1
	fi

	log "Creating or updating Argo CD public ALB ingress"
	kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${ARGOCD_INGRESS_NAME}
  namespace: ${ARGOCD_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: ${ARGOCD_ALB_SCHEME}
    alb.ingress.kubernetes.io/target-type: ${ARGOCD_TARGET_TYPE}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: ${ARGOCD_ACM_CERTIFICATE_ARN}
    alb.ingress.kubernetes.io/backend-protocol: HTTP
spec:
  rules:
    - host: ${ARGOCD_HOSTNAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${ARGOCD_SERVICE_NAME}
                port:
                  number: ${ARGOCD_SERVICE_PORT}
EOF

	kubectl -n "$ARGOCD_NAMESPACE" get ingress "$ARGOCD_INGRESS_NAME"
}

main() {
	require_cmd aws
	require_cmd kubectl
	require_cmd helm

	log "Preparing kubeconfig for ${CLUSTER_NAME} in ${REGION}"
	aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null

	install_controller
	create_argocd_ingress
}

main "$@"
