#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"
REPO_ROOT="$(cd "${DIR}/.." && pwd)"
BASE_DIR="${DIR}"

log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

usage() {
	cat <<'EOF'
Usage: git-sync/aws-gc.sh [options]

Options:
	-h, --help                  Show this help.

Behavior:
	- Finds all *.stack.yaml files recursively under git-sync/.
	- Builds stack names as TenantId-EnvId-RootName (same as aws-deploy.sh).
	- Lists current CloudFormation stacks in this account/region.
	- If a current stack is not in the managed set:
	  * If termination protection is enabled, skip it.
	  * Otherwise, delete the stack.
EOF
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "ERROR: required command not found: $1" >&2
		exit 1
	}
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-h|--help)
				usage
				exit 0
				;;
			*)
				echo "ERROR: unknown option: $1" >&2
				usage
				exit 1
				;;
		esac
	done
}

stack_root_name() {
	local file="$1"
	local base
	base="$(basename "${file}")"
	echo "${base%%.*}"
}

yaml_value() {
	local file="$1"
	local key="$2"
	awk -F: -v k="$key" '
		$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
			sub(/^[[:space:]]+/, "", $2)
			sub(/[[:space:]]+$/, "", $2)
			gsub(/^"|"$/, "", $2)
			gsub(/^'\''|'\''$/, "", $2)
			print $2
			exit
		}
	' "$file"
}

list_stack_files() {
	find "${BASE_DIR}" -type f -name '*.stack.yaml' | sort
}

build_managed_stack_set_file() {
	local out_file="$1"
	local file tenant_id env_id root_name stack_name

	: > "${out_file}"
	while IFS= read -r file; do
		tenant_id="$(yaml_value "${file}" "TenantId")"
		env_id="$(yaml_value "${file}" "EnvId")"

		if [[ -z "${tenant_id}" || -z "${env_id}" ]]; then
			log "SKIP  missing TenantId/EnvId in ${file#${REPO_ROOT}/}"
			continue
		fi

		root_name="$(stack_root_name "${file}")"
		stack_name="${tenant_id}-${env_id}-${root_name}"
		echo "${stack_name}" >> "${out_file}"
	done < <(list_stack_files)

	sort -u -o "${out_file}" "${out_file}"
}

list_current_stack_names() {
	aws cloudformation list-stacks \
		--stack-status-filter \
			CREATE_IN_PROGRESS CREATE_FAILED CREATE_COMPLETE \
			ROLLBACK_IN_PROGRESS ROLLBACK_FAILED ROLLBACK_COMPLETE \
			DELETE_IN_PROGRESS DELETE_FAILED \
			UPDATE_IN_PROGRESS UPDATE_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_COMPLETE \
			UPDATE_ROLLBACK_IN_PROGRESS UPDATE_ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_ROLLBACK_COMPLETE \
			REVIEW_IN_PROGRESS \
			IMPORT_IN_PROGRESS IMPORT_COMPLETE IMPORT_ROLLBACK_IN_PROGRESS IMPORT_ROLLBACK_FAILED IMPORT_ROLLBACK_COMPLETE \
		--query 'StackSummaries[].StackName' \
		--output text | tr '\t' '\n' | sed '/^[[:space:]]*$/d' | sort -u
}

is_stack_managed() {
	local stack_name="$1"
	local managed_set_file="$2"
	grep -Fxq "${stack_name}" "${managed_set_file}"
}

is_termination_protected() {
	local stack_name="$1"
	local enabled

	enabled="$(aws cloudformation describe-stacks \
		--stack-name "${stack_name}" \
		--query 'Stacks[0].EnableTerminationProtection' \
		--output text 2>/dev/null || true)"

	[[ "${enabled}" == "True" ]]
}

gc_unmanaged_stacks() {
	local managed_set_file="$1"
	local stack_name

	while IFS= read -r stack_name; do
		if is_stack_managed "${stack_name}" "${managed_set_file}"; then
			log "KEEP  stack=${stack_name}"
			continue
		fi

		if is_termination_protected "${stack_name}"; then
			log "SKIP  stack=${stack_name} termination-protected=true"
			continue
		fi

		log "DELETE stack=${stack_name} termination-protected=false"
		aws cloudformation delete-stack --stack-name "${stack_name}"
	done < <(list_current_stack_names)
}

main() {
	parse_args "$@"
	require_cmd aws
	require_cmd find
	require_cmd sort
	require_cmd awk
	require_cmd sed
	require_cmd grep

	if [[ ! -d "${BASE_DIR}" ]]; then
		echo "ERROR: base directory not found: ${BASE_DIR}" >&2
		exit 1
	fi

	log "script [$0] started dir[${DIR}] base-dir[${BASE_DIR}]"

	local managed_set_file
	managed_set_file="$(mktemp)"
	trap 'rm -f "${managed_set_file}"' EXIT

	build_managed_stack_set_file "${managed_set_file}"
	log "managed stack names count=$(wc -l < "${managed_set_file}" | tr -d ' ')"

	gc_unmanaged_stacks "${managed_set_file}"

	log "script [$0] completed"
}

main "$@"
