#!/usr/bin/env bash
set -euo pipefail

# Night scale-down script:
# 1) Snapshot current Deployment/StatefulSet replica counts
# 2) Scale selected namespaces down to zero
# 3) Delete NAT routes and NAT gateways in the EKS VPC
#
# This aggressively reduces cost and will break outbound access from private
# subnets until NAT is recreated and routes are restored.

CLUSTER_NAME="${EKS_CLUSTER:-gitops-eks}"
REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}}"
SNAPSHOT_FILE="${SNAPSHOT_FILE:-/tmp/${CLUSTER_NAME}-replicas-$(date +%Y%m%d-%H%M%S).json}"
AUTO_ACK="${AUTO_ACK:-false}"

# Comma-separated namespaces to scale down.
# Include kube-system if you want max savings (for example CoreDNS on Fargate).
SCALE_NAMESPACES="${SCALE_NAMESPACES:-argocd,default,kube-system}"

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
	local prompt="$1"
	if [[ "$AUTO_ACK" == "true" ]]; then
		echo "AUTO_ACK=true, proceeding without prompt"
		return 0
	fi
	local answer
	read -r -p "$prompt [y/N]: " answer
	answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
	[[ "$answer" == "y" || "$answer" == "yes" ]]
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--ack)
				AUTO_ACK=true
				shift
				;;
			*)
				echo "ERROR: unknown argument: $1" >&2
				echo "Usage: $0 [--ack]" >&2
				exit 1
				;;
		esac
	done
}

delete_nat_routes() {
	local vpc_id="$1"
	local nat_id="$2"

	# Find all route tables in the VPC that point to this NAT gateway.
	local route_entries
	route_entries=$(aws ec2 describe-route-tables \
		--region "$REGION" \
		--filters "Name=vpc-id,Values=${vpc_id}" \
		--query "RouteTables[].{rtb:RouteTableId,routes:Routes[?NatGatewayId=='${nat_id}'].DestinationCidrBlock}" \
		--output json)

	echo "$route_entries" | jq -r '.[] | .rtb as $rtb | .routes[]? | "\($rtb) \(.)"' | while read -r rtb_id cidr; do
		if [[ -n "$rtb_id" && -n "$cidr" ]]; then
			echo "Removing route ${cidr} from ${rtb_id} (nat: ${nat_id})"
			aws ec2 delete-route \
				--region "$REGION" \
				--route-table-id "$rtb_id" \
				--destination-cidr-block "$cidr" >/dev/null || true
		fi
	done
}

scale_namespace_workloads_to_zero() {
	local ns="$1"

	if ! kubectl get ns "$ns" >/dev/null 2>&1; then
		echo "Namespace ${ns} not found, skipping"
		return
	fi

	echo "Scaling deployments in ${ns} to 0"
	kubectl -n "$ns" get deploy -o name 2>/dev/null | while read -r obj; do
		[[ -z "$obj" ]] && continue
		kubectl -n "$ns" scale "$obj" --replicas=0 >/dev/null || true
	done

	echo "Scaling statefulsets in ${ns} to 0"
	kubectl -n "$ns" get statefulset -o name 2>/dev/null | while read -r obj; do
		[[ -z "$obj" ]] && continue
		kubectl -n "$ns" scale "$obj" --replicas=0 >/dev/null || true
	done
}

main() {
	parse_args "$@"

	require_cmd aws
	require_cmd kubectl
	require_cmd jq

	log "Preparing kubeconfig for ${CLUSTER_NAME} in ${REGION}"
	aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null

	log "Capturing replica snapshot to ${SNAPSHOT_FILE}"
	kubectl get deploy,statefulset -A -o json | jq '{
		cluster: env.CLUSTER_NAME,
		region: env.REGION,
		capturedAt: now,
		items: [
			.items[] | {
				namespace: .metadata.namespace,
				kind: .kind,
				name: .metadata.name,
				replicas: (.spec.replicas // 0)
			}
		]
	}' > "$SNAPSHOT_FILE"
	echo "Snapshot written: $SNAPSHOT_FILE"

	log "Scaling workloads to zero"
	IFS=',' read -r -a namespaces <<< "$SCALE_NAMESPACES"
	for ns in "${namespaces[@]}"; do
		ns_trimmed="$(echo "$ns" | xargs)"
		[[ -z "$ns_trimmed" ]] && continue
		scale_namespace_workloads_to_zero "$ns_trimmed"
	done

	log "Finding EKS VPC and NAT gateways"
	local vpc_id
	vpc_id=$(aws eks describe-cluster \
		--name "$CLUSTER_NAME" \
		--region "$REGION" \
		--query 'cluster.resourcesVpcConfig.vpcId' \
		--output text)

	if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
		echo "ERROR: could not resolve VPC ID from cluster"
		exit 1
	fi

	echo "Cluster VPC: $vpc_id"

	local nat_ids
	nat_ids=$(aws ec2 describe-nat-gateways \
		--region "$REGION" \
		--filter "Name=vpc-id,Values=${vpc_id}" "Name=state,Values=available,pending" \
		--query 'NatGateways[].NatGatewayId' \
		--output text)

	if [[ -z "$nat_ids" || "$nat_ids" == "None" ]]; then
		echo "No active NAT gateways found in $vpc_id"
	else
		echo "NAT gateways to delete: $nat_ids"
		if ! confirm "Proceed with deleting NAT gateways and NAT routes in VPC ${vpc_id}?"; then
			echo "Skipping NAT deletion. Workloads are already scaled to zero."
			exit 0
		fi

		for nat_id in $nat_ids; do
			delete_nat_routes "$vpc_id" "$nat_id"
			echo "Deleting NAT gateway ${nat_id}"
			aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$nat_id" >/dev/null || true
		done
	fi

	log "Scale-down complete"
	echo "Workloads scaled to zero for namespaces: $SCALE_NAMESPACES"
	echo "Replica snapshot: $SNAPSHOT_FILE"
	echo "NAT gateways/routes deletion requested where found"
}

main "$@"
