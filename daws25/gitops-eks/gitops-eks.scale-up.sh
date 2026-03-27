#!/usr/bin/env bash
set -euo pipefail

# Morning scale-up script:
# 1) Restore NAT gateway (if missing) and private subnet default routes
# 2) Restore Deployment/StatefulSet replicas from snapshot

CLUSTER_NAME="${EKS_CLUSTER:-gitops-eks}"
REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}}"
SNAPSHOT_FILE="${SNAPSHOT_FILE:-}"
NAT_EIP_ALLOCATION_ID="${NAT_EIP_ALLOCATION_ID:-}"
NAT_ROUTE_CIDR="${NAT_ROUTE_CIDR:-0.0.0.0/0}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-180s}"

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

find_latest_snapshot() {
	ls -1t "/tmp/${CLUSTER_NAME}-replicas-"*.json 2>/dev/null | head -n 1 || true
}

route_table_for_subnet() {
	local subnet_id="$1"
	local rtb
	rtb=$(aws ec2 describe-route-tables \
		--region "$REGION" \
		--filters "Name=association.subnet-id,Values=${subnet_id}" \
		--query 'RouteTables[0].RouteTableId' \
		--output text)
	if [[ -z "$rtb" || "$rtb" == "None" ]]; then
		rtb=$(aws ec2 describe-route-tables \
			--region "$REGION" \
			--filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.main,Values=true" \
			--query 'RouteTables[0].RouteTableId' \
			--output text)
	fi
	echo "$rtb"
}

is_public_route_table() {
	local rtb_id="$1"
	local igw
	igw=$(aws ec2 describe-route-tables \
		--region "$REGION" \
		--route-table-ids "$rtb_id" \
		--query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0' && starts_with(GatewayId, 'igw-')].GatewayId | [0]" \
		--output text)
	[[ -n "$igw" && "$igw" != "None" ]]
}

ensure_nat_gateway() {
	local nat_id
	nat_id=$(aws ec2 describe-nat-gateways \
		--region "$REGION" \
		--filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available,pending" \
		--query 'NatGateways[0].NatGatewayId' \
		--output text)

	if [[ -n "$nat_id" && "$nat_id" != "None" ]]; then
		echo "$nat_id"
		return
	fi

	log "No NAT gateway found, creating one"

	local public_subnet=""
	for subnet in $CLUSTER_SUBNETS; do
		local rtb
		rtb=$(route_table_for_subnet "$subnet")
		if [[ -n "$rtb" && "$rtb" != "None" ]] && is_public_route_table "$rtb"; then
			public_subnet="$subnet"
			break
		fi
	done

	if [[ -z "$public_subnet" ]]; then
		echo "ERROR: Could not find a public subnet among cluster subnets to place NAT gateway" >&2
		exit 1
	fi

	local alloc_id="$NAT_EIP_ALLOCATION_ID"
	if [[ -z "$alloc_id" ]]; then
		alloc_id=$(aws ec2 allocate-address \
			--region "$REGION" \
			--domain vpc \
			--query 'AllocationId' \
			--output text)
		echo "Allocated EIP: $alloc_id"
	fi

	nat_id=$(aws ec2 create-nat-gateway \
		--region "$REGION" \
		--subnet-id "$public_subnet" \
		--allocation-id "$alloc_id" \
		--query 'NatGateway.NatGatewayId' \
		--output text)

	echo "Created NAT gateway: $nat_id (subnet: $public_subnet)"
	aws ec2 wait nat-gateway-available --region "$REGION" --nat-gateway-ids "$nat_id"
	echo "$nat_id"
}

ensure_private_routes_to_nat() {
	local nat_id="$1"
	local route_tables

	route_tables=$(aws ec2 describe-route-tables \
		--region "$REGION" \
		--filters "Name=vpc-id,Values=${VPC_ID}" \
		--query 'RouteTables[].RouteTableId' \
		--output text)

	for rtb in $route_tables; do
		if is_public_route_table "$rtb"; then
			continue
		fi

		local has_default
		has_default=$(aws ec2 describe-route-tables \
			--region "$REGION" \
			--route-table-ids "$rtb" \
			--query "RouteTables[0].Routes[?DestinationCidrBlock=='${NAT_ROUTE_CIDR}'] | length(@)" \
			--output text)

		if [[ "$has_default" == "0" ]]; then
			echo "Creating ${NAT_ROUTE_CIDR} route in ${rtb} -> ${nat_id}"
			aws ec2 create-route \
				--region "$REGION" \
				--route-table-id "$rtb" \
				--destination-cidr-block "$NAT_ROUTE_CIDR" \
				--nat-gateway-id "$nat_id" >/dev/null
		else
			echo "Replacing ${NAT_ROUTE_CIDR} route in ${rtb} -> ${nat_id}"
			aws ec2 replace-route \
				--region "$REGION" \
				--route-table-id "$rtb" \
				--destination-cidr-block "$NAT_ROUTE_CIDR" \
				--nat-gateway-id "$nat_id" >/dev/null || true
		fi
	done
}

restore_replicas_from_snapshot() {
	local snapshot="$1"
	local items

	items=$(jq -r '.items[] | "\(.namespace)|\(.kind)|\(.name)|\(.replicas)"' "$snapshot")
	while IFS='|' read -r ns kind name replicas; do
		[[ -z "$ns" || -z "$kind" || -z "$name" ]] && continue
		[[ -z "$replicas" || "$replicas" == "null" ]] && replicas=0

		local resource=""
		case "$kind" in
			Deployment) resource="deployment" ;;
			StatefulSet) resource="statefulset" ;;
			*) continue ;;
		esac

		if kubectl -n "$ns" get "$resource/$name" >/dev/null 2>&1; then
			echo "Scaling $ns/$resource/$name -> $replicas"
			kubectl -n "$ns" scale "$resource/$name" --replicas="$replicas" >/dev/null || true
		fi
	done <<< "$items"
}

wait_rollouts_from_snapshot() {
	local snapshot="$1"
	local items

	items=$(jq -r '.items[] | select((.replicas // 0) > 0) | "\(.namespace)|\(.kind)|\(.name)"' "$snapshot")
	while IFS='|' read -r ns kind name; do
		[[ -z "$ns" || -z "$kind" || -z "$name" ]] && continue

		case "$kind" in
			Deployment)
				kubectl -n "$ns" rollout status "deployment/$name" --timeout="$ROLLOUT_TIMEOUT" || true
				;;
			StatefulSet)
				kubectl -n "$ns" rollout status "statefulset/$name" --timeout="$ROLLOUT_TIMEOUT" || true
				;;
		esac
	done <<< "$items"
}

main() {
	require_cmd aws
	require_cmd kubectl
	require_cmd jq

	if [[ -z "$SNAPSHOT_FILE" ]]; then
		SNAPSHOT_FILE="$(find_latest_snapshot)"
	fi

	if [[ -z "$SNAPSHOT_FILE" || ! -f "$SNAPSHOT_FILE" ]]; then
		echo "ERROR: snapshot file not found. Set SNAPSHOT_FILE=/tmp/${CLUSTER_NAME}-replicas-<timestamp>.json" >&2
		exit 1
	fi

	log "Preparing kubeconfig for ${CLUSTER_NAME} in ${REGION}"
	aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null

	log "Resolving VPC and subnets"
	VPC_ID=$(aws eks describe-cluster \
		--name "$CLUSTER_NAME" \
		--region "$REGION" \
		--query 'cluster.resourcesVpcConfig.vpcId' \
		--output text)

	CLUSTER_SUBNETS=$(aws eks describe-cluster \
		--name "$CLUSTER_NAME" \
		--region "$REGION" \
		--query 'cluster.resourcesVpcConfig.subnetIds[]' \
		--output text)

	if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
		echo "ERROR: Could not resolve VPC for cluster" >&2
		exit 1
	fi

	log "Ensuring NAT gateway and private routes"
	nat_id="$(ensure_nat_gateway)"
	ensure_private_routes_to_nat "$nat_id"

	log "Restoring replicas from snapshot: ${SNAPSHOT_FILE}"
	restore_replicas_from_snapshot "$SNAPSHOT_FILE"

	log "Waiting for rollouts"
	wait_rollouts_from_snapshot "$SNAPSHOT_FILE"

	log "Scale-up complete"
	kubectl get pods -A
}

main "$@"
