#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"

# ── Default: GIT_SYNC_BRANCH ────────────────────────────────────
export GIT_SYNC_BRANCH="${GIT_SYNC_BRANCH:-main}"

# ── Lookup: REPOSITORY_LINK_ID (first CodeConnections repo link) ─
if [[ -z "${REPOSITORY_LINK_ID:-}" ]]; then
  REPOSITORY_LINK_ID="$(
    aws codeconnections list-repository-links \
      --query 'RepositoryLinks[0].RepositoryLinkId' \
      --output text
  )"
  if [[ -z "${REPOSITORY_LINK_ID}" || "${REPOSITORY_LINK_ID}" == "None" ]]; then
    echo "ERROR: no repository link found in CodeConnections" >&2
    exit 1
  fi
  export REPOSITORY_LINK_ID
fi

# ── Lookup: GIT_SYNC_ROLE_ARN (first IAM role matching git-sync) ─
if [[ -z "${GIT_SYNC_ROLE_ARN:-}" ]]; then
  GIT_SYNC_ROLE_ARN="$(
    aws iam list-roles \
      --query "Roles[?contains(RoleName,'git-sync')].Arn | [0]" \
      --output text
  )"
  if [[ -z "${GIT_SYNC_ROLE_ARN}" || "${GIT_SYNC_ROLE_ARN}" == "None" ]]; then
    echo "ERROR: no IAM role matching 'git-sync' found" >&2
    exit 1
  fi
  export GIT_SYNC_ROLE_ARN
fi

# ── Lookup: CLOUDFRONT_DISTRIBUTION_IDS (from Presence stack) ────
if [[ -z "${CLOUDFRONT_DISTRIBUTION_IDS:-}" ]]; then
  CLOUDFRONT_DISTRIBUTION_IDS="$(
    aws cloudformation describe-stacks \
      --stack-name Presence-Main-cloudfront-distribution \
      --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue | [0]" \
      --output text 2>/dev/null || true
  )"
  if [[ -z "${CLOUDFRONT_DISTRIBUTION_IDS}" || "${CLOUDFRONT_DISTRIBUTION_IDS}" == "None" ]]; then
    echo "WARN: no CloudFront distribution found in Presence-Main-cloudfront-distribution stack (invalidation will be skipped)" >&2
    CLOUDFRONT_DISTRIBUTION_IDS=""
  fi
  export CLOUDFRONT_DISTRIBUTION_IDS
fi

echo "REPOSITORY_LINK_ID=${REPOSITORY_LINK_ID}"
echo "GIT_SYNC_ROLE_ARN=${GIT_SYNC_ROLE_ARN}"
echo "GIT_SYNC_BRANCH=${GIT_SYNC_BRANCH}"
echo "CLOUDFRONT_DISTRIBUTION_IDS=${CLOUDFRONT_DISTRIBUTION_IDS}"

aws sts get-caller-identity
sleep 10
echo "Starting GC..."
"${DIR}/aws-gc.sh"
echo "GC complete, proceeding to deploy..."
sleep 10
"${DIR}/aws-deploy.sh"
echo "Done"