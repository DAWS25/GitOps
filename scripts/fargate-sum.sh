#!/usr/bin/env bash
# fargate-sum.sh — Summarizes EKS Fargate compute usage and estimates cost
# Pricing (us-east-1, as of 2025):
#   vCPU: $0.04048 per vCPU-hour
#   Memory: $0.004445 per GB-hour
set -euo pipefail

VCPU_PRICE_PER_HOUR=0.04048   # USD per vCPU-hour
MEM_PRICE_PER_GB_HOUR=0.004445 # USD per GB-hour

REGION="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo "us-east-1")}"

echo "========================================"
echo " EKS Fargate Compute Usage & Cost Report"
echo " Region: $REGION"
echo "========================================"

CLUSTERS=$(aws eks list-clusters --region "$REGION" --query 'clusters[]' --output text)

if [[ -z "$CLUSTERS" ]]; then
  echo "No EKS clusters found in region $REGION."
  exit 0
fi

total_vcpu=0
total_mem_gb=0
total_pods=0
STATS_FILE=$(mktemp)

for CLUSTER in $CLUSTERS; do
  # Check if the cluster has any Fargate profiles
  FARGATE_PROFILES=$(aws eks list-fargate-profiles \
    --cluster-name "$CLUSTER" \
    --region "$REGION" \
    --query 'fargateProfileNames[]' \
    --output text 2>/dev/null || true)

  if [[ -z "$FARGATE_PROFILES" ]]; then
    echo ""
    echo "Cluster: $CLUSTER — no Fargate profiles, skipping."
    continue
  fi

  echo ""
  echo "Cluster: $CLUSTER"
  echo "  Fargate profiles: $(echo "$FARGATE_PROFILES" | tr '\t' ', ')"

  # Get kubeconfig for this cluster
  aws eks update-kubeconfig \
    --name "$CLUSTER" \
    --region "$REGION" \
    --alias "$CLUSTER" \
    --kubeconfig /tmp/fargate-sum-kubeconfig.yaml \
    >/dev/null 2>&1

  # List all pods running on Fargate nodes (node name starts with "fargate-")
  FARGATE_PODS=$(kubectl \
    --kubeconfig /tmp/fargate-sum-kubeconfig.yaml \
    get pods -A \
    --field-selector=status.phase=Running \
    -o json 2>/dev/null | \
    jq -r '
      .items[]
      | select(.spec.nodeName and (.spec.nodeName | startswith("fargate-")))
      | {
          ns: .metadata.namespace,
          name: .metadata.name,
          node: .spec.nodeName,
          containers: .spec.containers
        }
    ')

  if [[ -z "$FARGATE_PODS" ]]; then
    echo "  No running Fargate pods found."
    continue
  fi

  # For each Fargate pod, get per-pod resource requests
  kubectl \
    --kubeconfig /tmp/fargate-sum-kubeconfig.yaml \
    get pods -A \
    --field-selector=status.phase=Running \
    -o json 2>/dev/null | \
  jq -r --argjson vcpu_price "$VCPU_PRICE_PER_HOUR" \
         --argjson mem_price "$MEM_PRICE_PER_GB_HOUR" '
    def parse_cpu(v):
      if v == null then 0.25          # Fargate minimum: 0.25 vCPU
      elif (v | endswith("m")) then (v[:-1] | tonumber) / 1000
      else (v | tonumber)
      end;

    def parse_mem_gb(v):
      if v == null then 0.5           # Fargate minimum: 0.5 GB
      elif (v | endswith("Mi")) then (v[:-2] | tonumber) / 1024
      elif (v | endswith("Gi")) then (v[:-2] | tonumber)
      elif (v | endswith("M")) then (v[:-1] | tonumber) / 1024
      elif (v | endswith("G")) then (v[:-1] | tonumber)
      elif (v | endswith("Ki")) then (v[:-2] | tonumber) / 1048576
      else (v | tonumber) / 1073741824
      end;

    [
      .items[]
      | select(.spec.nodeName and (.spec.nodeName | startswith("fargate-")))
      | {
          ns: .metadata.namespace,
          name: .metadata.name,
          vcpu: ([.spec.containers[].resources.requests.cpu? | parse_cpu(.)] | add // 0.25),
          mem_gb: ([.spec.containers[].resources.requests.memory? | parse_mem_gb(.)] | add // 0.5)
        }
    ]
    | (. | length) as $count
    | ([ .[].vcpu ] | add // 0) as $total_vcpu
    | ([ .[].mem_gb ] | add // 0) as $total_mem
    | "  Fargate pods running: \($count)",
      "  Total vCPU requested:  \($total_vcpu | . * 1000 | round / 1000)",
      "  Total Memory (GB):     \($total_mem | . * 1000 | round / 1000)",
      "",
      "  --- Hourly cost estimate ---",
      "  vCPU cost/hr:   $\(($total_vcpu * $vcpu_price) | . * 10000 | round / 10000)",
      "  Memory cost/hr: $\(($total_mem * $mem_price) | . * 10000 | round / 10000)",
      "  Total/hr:       $\((($total_vcpu * $vcpu_price) + ($total_mem * $mem_price)) | . * 10000 | round / 10000)",
      "  Total/day:      $\(((($total_vcpu * $vcpu_price) + ($total_mem * $mem_price)) * 24) | . * 100 | round / 100)",
      "  Total/month:    $\(((($total_vcpu * $vcpu_price) + ($total_mem * $mem_price)) * 24 * 30) | . * 100 | round / 100)",
      "__STATS__:\($count):\($total_vcpu):\($total_mem)"
  ' | while IFS= read -r line; do
      if [[ "$line" == __STATS__:* ]]; then
        echo "$line" >> "$STATS_FILE"
      else
        echo "$line"
      fi
    done

done

rm -f /tmp/fargate-sum-kubeconfig.yaml

# Accumulate totals from stats file
while IFS= read -r line; do
  IFS=: read -r _ pods vcpu mem <<< "$line"
  total_pods=$((total_pods + pods))
  total_vcpu=$(echo "$total_vcpu + $vcpu" | bc)
  total_mem_gb=$(echo "$total_mem_gb + $mem" | bc)
done < "$STATS_FILE"
rm -f "$STATS_FILE"

echo ""
echo "========================================"
echo " GRAND TOTAL ACROSS ALL CLUSTERS"
echo "========================================"
# Recompute totals (shell bc arithmetic since we're post-pipe)
python3 - <<PYEOF
vcpu      = $total_vcpu
mem_gb    = $total_mem_gb
vcpu_p    = $VCPU_PRICE_PER_HOUR
mem_p     = $MEM_PRICE_PER_GB_HOUR
hourly    = vcpu * vcpu_p + mem_gb * mem_p
print(f"  Total vCPU:     {vcpu:.3f}")
print(f"  Total Mem (GB): {mem_gb:.3f}")
print(f"  Cost/hour:  \${hourly:.4f}")
print(f"  Cost/day:   \${hourly * 24:.2f}")
print(f"  Cost/month: \${hourly * 24 * 30:.2f}")
print()
print(f"  Pricing basis (us-east-1):")
print(f"    vCPU:   \${vcpu_p}/vCPU-hr")
print(f"    Memory: \${mem_p}/GB-hr")
PYEOF
