#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"

log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Extract a scalar value from a simple YAML file
yaml_value() {
	local file="$1" key="$2"
	awk -F: -v k="$key" '
		$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
			sub(/^[[:space:]]+/, "", $2); sub(/[[:space:]]+$/, "", $2)
			gsub(/^"|"$|^'"'"'|'"'"'$/, "", $2)
			print $2; exit
		}
	' "$file"
}

# Build a sorted list of stack names derived from *.stack.yaml files in git-sync/
build_managed_names() {
	local file tenant env root
	find "${DIR}" -type f -name '*.stack.yaml' | sort | while IFS= read -r file; do
		tenant="$(yaml_value "${file}" "TenantId")"
		env="$(yaml_value "${file}" "EnvId")"
		[[ -z "${tenant}" || -z "${env}" ]] && continue
		root="$(basename "${file%%.*}")"
		echo "${tenant}-${env}-${root}"
	done | sort -u
}

# Delete all stacks currently in ROLLBACK_COMPLETE
delete_rollback_complete() {
	local name
	log "Checking for ROLLBACK_COMPLETE stacks..."
	while IFS= read -r name; do
		[[ -z "${name}" ]] && continue
		log "DELETE ${name} (ROLLBACK_COMPLETE)"
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
