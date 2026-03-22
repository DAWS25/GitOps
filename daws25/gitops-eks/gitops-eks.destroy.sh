#!/usr/bin/env bash
set -euo pipefail

# Deletes the GitOps EKS CloudFormation stack and waits for completion.
# Defaults:
#   STACK_NAME=${TENANT_ID}-gitops-eks
#   REGION from AWS_DEFAULT_REGION/AWS_REGION/aws config (fallback us-east-1)

TENANT_ID="${TENANT_ID:-gitops}"
STACK_NAME="${STACK_NAME:-${TENANT_ID}-gitops-eks}"
REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}}"
AUTO_ACK="${AUTO_ACK:-false}"
WAIT_FOR_DELETE="${WAIT_FOR_DELETE:-true}"
KUBECONFIG_FILE="${KUBECONFIG:-$HOME/.kube/config}"

usage() {
	cat <<'EOF'
Usage: gitops-eks.destroy.sh [options]

Options:
	--stack-name <name>   CloudFormation stack name (default: ${TENANT_ID}-gitops-eks)
	--region <region>     AWS region (default: env/config)
	--yes                 Skip interactive confirmation
	--no-wait             Do not wait for stack deletion completion
	-h, --help            Show this help

Examples:
	./gitops-eks.destroy.sh --yes
	./gitops-eks.destroy.sh --stack-name tenant1-gitops-eks --region us-east-1
EOF
}

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

confirm() {
	if [[ "$AUTO_ACK" == "true" ]]; then
		echo "AUTO_ACK=true, proceeding without prompt"
		return 0
	fi

	local answer
	read -r -p "Delete CloudFormation stack '${STACK_NAME}' in region '${REGION}'? [y/N]: " answer
	answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
	[[ "$answer" == "y" || "$answer" == "yes" ]]
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--stack-name)
				STACK_NAME="$2"
				shift 2
				;;
			--region)
				REGION="$2"
				shift 2
				;;
			--yes)
				AUTO_ACK=true
				shift
				;;
			--no-wait)
				WAIT_FOR_DELETE=false
				shift
				;;
			-h|--help)
				usage
				exit 0
				;;
			*)
				echo "ERROR: unknown argument '$1'" >&2
				usage
				exit 1
				;;
		esac
	done
}

stack_exists() {
	local status
	status=$(aws cloudformation describe-stacks \
		--stack-name "$STACK_NAME" \
		--region "$REGION" \
		--query 'Stacks[0].StackStatus' \
		--output text 2>/dev/null || true)

	[[ -n "$status" && "$status" != "None" ]]
}

cleanup_kubeconfig() {
	if [[ ! -f "$KUBECONFIG_FILE" ]]; then
		return
	fi

	log "Cleaning kubeconfig contexts for cluster '${STACK_NAME}'"
	kubectl config delete-context "$STACK_NAME" --kubeconfig "$KUBECONFIG_FILE" >/dev/null 2>&1 || true
	kubectl config delete-cluster "$STACK_NAME" --kubeconfig "$KUBECONFIG_FILE" >/dev/null 2>&1 || true
	kubectl config delete-user "$STACK_NAME" --kubeconfig "$KUBECONFIG_FILE" >/dev/null 2>&1 || true
}

main() {
	parse_args "$@"

	require_cmd aws
	require_cmd kubectl

	log "Target stack"
	echo "STACK_NAME: $STACK_NAME"
	echo "REGION:     $REGION"

	if ! stack_exists; then
		echo "Stack '$STACK_NAME' does not exist in region '$REGION'. Nothing to delete."
		cleanup_kubeconfig
		exit 0
	fi

	if ! confirm; then
		echo "Aborted by user."
		exit 1
	fi

	# Best effort: disable termination protection if enabled.
	log "Disabling termination protection (best effort)"
	aws cloudformation update-termination-protection \
		--stack-name "$STACK_NAME" \
		--region "$REGION" \
		--no-enable-termination-protection >/dev/null 2>&1 || true

	log "Deleting stack '${STACK_NAME}'"
	aws cloudformation delete-stack \
		--stack-name "$STACK_NAME" \
		--region "$REGION"

	if [[ "$WAIT_FOR_DELETE" == "true" ]]; then
		log "Waiting for delete to complete"
		aws cloudformation wait stack-delete-complete \
			--stack-name "$STACK_NAME" \
			--region "$REGION"
		echo "Stack '${STACK_NAME}' deleted successfully."
	else
		echo "Delete requested. Not waiting for completion (--no-wait)."
	fi

	cleanup_kubeconfig
}

main "$@"
