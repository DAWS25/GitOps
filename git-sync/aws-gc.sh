#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"

# shellcheck source=aws-lib.sh
source "${DIR}/aws-lib.sh"

# Build a sorted list of stack names derived from *.stack.yaml files in git-sync/
build_managed_names() {
	local file name
	find "${DIR}" -type f -name '*.stack.yaml' | sort | while IFS= read -r file; do
		name="$(stack_name_from_file "${file}")"
		[[ -z "${name}" || "${name}" == "-" ]] && continue
		echo "${name}"
	done | sort -u
}

# Empty an S3 bucket: policy, all versions, delete markers, and objects
empty_bucket() {
	local bucket="$1"
	log "EMPTY bucket=${bucket}"

	# Remove bucket policy first (so no policy blocks deletes)
	aws s3api delete-bucket-policy --bucket "${bucket}" 2>/dev/null || true

	# Remove all objects (non-versioned)
	aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true

	# Remove all versions and delete markers in batches
	local query objects
	for query in "Versions" "DeleteMarkers"; do
		while true; do
			objects="$(aws s3api list-object-versions --bucket "${bucket}" \
				--query "${query}[0:1000].{Key:Key,VersionId:VersionId}" \
				--output json 2>/dev/null || echo "[]")"
			[[ "${objects}" == "[]" || "${objects}" == "null" ]] && break
			aws s3api delete-objects --bucket "${bucket}" \
				--delete "{\"Objects\":${objects},\"Quiet\":true}" \
				--output json >/dev/null 2>/dev/null || break
		done
	done
}

# For a given stack, find any output values that are S3 bucket names and empty them
empty_stack_buckets() {
	local stack_name="$1"
	local buckets bucket

	buckets="$(aws cloudformation describe-stacks \
		--stack-name "${stack_name}" \
		--query 'Stacks[0].Outputs[].OutputValue' \
		--output text 2>/dev/null || true)"

	for bucket in ${buckets}; do
		# Check if the output value is actually an existing S3 bucket
		if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
			empty_bucket "${bucket}"
		fi
	done
}

# Delete all stacks currently in ROLLBACK_COMPLETE
delete_rollback_complete() {
	local name
	log "Checking for ROLLBACK_COMPLETE stacks..."
	while IFS= read -r name; do
		[[ -z "${name}" ]] && continue
		log "DELETE ${name} (ROLLBACK_COMPLETE)"
		empty_stack_buckets "${name}"
		aws cloudformation delete-stack --stack-name "${name}"
	done < <(aws cloudformation list-stacks \
		--stack-status-filter ROLLBACK_COMPLETE \
		--query 'StackSummaries[].StackName' \
		--output text | tr '\t' '\n' | grep -v '^$' || true)
}

# Delete active stacks that are not in the managed set (skip termination-protected)
delete_unmanaged() {
	local managed_file="$1" name protected
	log "Checking for unmanaged stacks..."
	while IFS= read -r name; do
		[[ -z "${name}" ]] && continue
		if grep -Fxq "${name}" "${managed_file}"; then
			log "KEEP  ${name}"
			continue
		fi
		protected="$(aws cloudformation describe-stacks \
			--stack-name "${name}" \
			--query 'Stacks[0].EnableTerminationProtection' \
			--output text 2>/dev/null || echo False)"
		if [[ "${protected}" == "True" ]]; then
			log "SKIP  ${name} (termination-protected)"
			continue
		fi
		log "DELETE ${name} (unmanaged)"
		empty_stack_buckets "${name}"
		aws cloudformation delete-stack --stack-name "${name}"
	done < <(aws cloudformation list-stacks \
		--stack-status-filter \
			CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE \
			CREATE_FAILED ROLLBACK_FAILED DELETE_FAILED UPDATE_ROLLBACK_FAILED \
		--query 'StackSummaries[].StackName' \
		--output text | tr '\t' '\n' | grep -v '^$' | sort -u || true)
}

main() {
	[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && {
		echo "Usage: aws-gc.sh [-h|--help]"
		echo "Deletes ROLLBACK_COMPLETE stacks and active stacks absent from git-sync/."
		exit 0
	}

	log "aws-gc started"

	managed_file="$(mktemp)"
	trap 'rm -f "${managed_file}"' EXIT

	build_managed_names > "${managed_file}"
	log "Managed stacks: $(wc -l < "${managed_file}" | tr -d ' ')"

	delete_rollback_complete
	delete_unmanaged "${managed_file}"

	log "aws-gc done"
}

main "$@"
