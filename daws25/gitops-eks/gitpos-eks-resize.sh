#!/usr/bin/env bash
# gitpos-eks-resize.sh — Removes unnecessary Fargate pods and halves resource
# requests/limits for all remaining pods.
#
# NOTE: Fargate bills at a minimum of 0.25 vCPU / 0.512 GB per pod regardless
# of requests. Setting requests below that floor won't reduce billing further,
# but it documents intent and improves scheduling on future node groups.
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo "us-east-1")}"
CLUSTER="${EKS_CLUSTER:-gitops-eks}"

echo "================================================"
echo " EKS Fargate Resize — $CLUSTER ($REGION)"
echo "================================================"

# ── 1. Update kubeconfig ──────────────────────────────────────────────────────
echo ""
echo ">> Updating kubeconfig..."
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1

# ── 2. Remove unnecessary components (scale to 0) ────────────────────────────
echo ""
echo ">> Scaling down unused ArgoCD components..."

kubectl scale deployment argocd-dex-server \
  -n argocd --replicas=0 2>/dev/null \
  && echo "   argocd-dex-server → 0 replicas" \
  || echo "   argocd-dex-server: already at 0 or not found"

kubectl scale deployment argocd-notifications-controller \
  -n argocd --replicas=0 2>/dev/null \
  && echo "   argocd-notifications-controller → 0 replicas" \
  || echo "   argocd-notifications-controller: already at 0 or not found"

# ── 3. Reduce redis-follower replicas ─────────────────────────────────────────
echo ""
echo ">> Reducing redis-follower to 1 replica..."
kubectl scale deployment redis-follower \
  -n default --replicas=1 2>/dev/null \
  && echo "   redis-follower → 1 replica" \
  || echo "   redis-follower: not found or already scaled"

# ── 4. Halve resource requests/limits for remaining deployments ───────────────
# For pods with NO requests set: Fargate minimum is 0.25 vCPU / 512Mi.
# We set half of that: 125m / 256Mi.
# For pods with explicit requests, we halve them (floor: 50m / 32Mi).
echo ""
echo ">> Patching resource requests to half for remaining ArgoCD deployments..."

patch_deployment() {
  local ns="$1"
  local name="$2"
  local cpu="$3"
  local mem="$4"
  kubectl patch deployment "$name" -n "$ns" --type='json' -p="[
    {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/resources\",
     \"value\": {
       \"requests\": {\"cpu\": \"$cpu\", \"memory\": \"$mem\"},
       \"limits\":   {\"cpu\": \"$cpu\", \"memory\": \"$mem\"}
     }
    }
  ]" 2>/dev/null \
    && echo "   $ns/$name → cpu=$cpu mem=$mem" \
    || echo "   $ns/$name: patch failed or not found"
}

patch_statefulset() {
  local ns="$1"
  local name="$2"
  local cpu="$3"
  local mem="$4"
  kubectl patch statefulset "$name" -n "$ns" --type='json' -p="[
    {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/resources\",
     \"value\": {
       \"requests\": {\"cpu\": \"$cpu\", \"memory\": \"$mem\"},
       \"limits\":   {\"cpu\": \"$cpu\", \"memory\": \"$mem\"}
     }
    }
  ]" 2>/dev/null \
    && echo "   $ns/$name → cpu=$cpu mem=$mem" \
    || echo "   $ns/$name: patch failed or not found"
}

# ArgoCD — currently no requests set; half of Fargate min (0.25 vCPU / 512Mi)
patch_deployment       argocd  argocd-applicationset-controller  125m  256Mi
patch_deployment       argocd  argocd-redis                       125m  256Mi
patch_deployment       argocd  argocd-repo-server                 125m  256Mi
patch_deployment       argocd  argocd-server                      125m  256Mi
patch_statefulset      argocd  argocd-application-controller      125m  256Mi

echo ""
echo ">> Patching resource requests to half for default namespace..."

# guestbook-ui — no requests set
patch_deployment  default  guestbook-ui    125m  256Mi

# redis-leader/follower — currently 100m / 100Mi → half = 50m / 50Mi
patch_deployment  default  redis-leader    50m   50Mi
patch_deployment  default  redis-follower  50m   50Mi

# ── 5. Wait for rollouts ──────────────────────────────────────────────────────
echo ""
echo ">> Waiting for rollouts to complete..."
for deploy in argocd-applicationset-controller argocd-redis argocd-repo-server argocd-server; do
  kubectl rollout status deployment/"$deploy" -n argocd --timeout=120s 2>/dev/null \
    && echo "   argocd/$deploy: ready" \
    || echo "   argocd/$deploy: timed out or error"
done
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=120s 2>/dev/null \
  && echo "   argocd/argocd-application-controller: ready" \
  || echo "   argocd/argocd-application-controller: timed out or error"

for deploy in guestbook-ui redis-leader redis-follower; do
  kubectl rollout status deployment/"$deploy" -n default --timeout=120s 2>/dev/null \
    && echo "   default/$deploy: ready" \
    || echo "   default/$deploy: timed out or error"
done

# ── 6. Final summary ──────────────────────────────────────────────────────────
echo ""
echo ">> Running cost summary..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../../scripts/fargate-sum.sh" ]]; then
  bash "$SCRIPT_DIR/../../scripts/fargate-sum.sh"
else
  kubectl get pods -A -o wide | grep fargate || echo "No Fargate pods found."
fi
