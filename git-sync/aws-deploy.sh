#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"
REPO_ROOT="$(cd "${DIR}/.." && pwd)"

BASE_DIR="${DIR}"
BRANCH="${GIT_SYNC_BRANCH:-main}"
REPOSITORY_LINK_ID="${REPOSITORY_LINK_ID:-}"
ROLE_ARN="${GIT_SYNC_ROLE_ARN:-}"
SLEEP_BETWEEN_STACKS_SECONDS=2
_SUMMARY=()
_LAST_ACTION=""

log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

load_repo_envrc() {
	local envrc_path="${REPO_ROOT}/.envrc"
	if [[ -f "${envrc_path}" ]]; then
		log "loading env from ${envrc_path}"
		set +u
		# shellcheck disable=SC1090
		source "${envrc_path}"
		set -u
	fi

	# Refresh runtime config from environment after sourcing .envrc
	BRANCH="${GIT_SYNC_BRANCH:-main}"
	REPOSITORY_LINK_ID="${REPOSITORY_LINK_ID:-}"
	ROLE_ARN="${GIT_SYNC_ROLE_ARN:-}"
}

usage() {
	cat <<'EOF'
Usage: git-sync/aws-deploy.sh [options]

Options:
	-h, --help                  Show this help.

Behavior:
	- Reads config from env vars: REPOSITORY_LINK_ID, GIT_SYNC_ROLE_ARN, GIT_SYNC_BRANCH.
	- Finds all *.stack.yaml files recursively under git-sync/ in name order.
	- Extracts TenantId and EnvId from each YAML file.
	- Computes RootName as the filename prefix before the first dot.
	- Builds stack name as TenantId-EnvId-RootName.
	- Bootstraps missing stacks with cloudformation deploy.
	- Verifies each stack reaches a successful terminal status before continuing.
	- Sleeps $SLEEP_BETWEEN_STACKS_SECONDS seconds between stack files.
	- Creates CFN_STACK_SYNC config using create-sync-configuration.
	- Skips stacks that already have a sync configuration.
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

	if [[ -z "${REPOSITORY_LINK_ID}" || -z "${ROLE_ARN}" || -z "${BRANCH}" ]]; then
		echo "ERROR: missing required env vars: REPOSITORY_LINK_ID, GIT_SYNC_ROLE_ARN, GIT_SYNC_BRANCH" >&2
		usage
		exit 1
	fi
}

to_repo_relative_path() {
	local abs="$1"
	local prefix="${REPO_ROOT}/"
	echo "${abs#${prefix}}"
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
			gsub(/^'"'"'|'"'"'$/, "", $2)
			gsub(/\r/, "", $2)
			print $2
			exit
		}
	' "$file"
}

yaml_section_key_values() {
	local file="$1"
	local section="$2"
	awk -v section="$section" '
		$0 ~ "^[[:space:]]*" section ":[[:space:]]*$" { in_section=1; next }
		in_section {
			if ($0 ~ "^[^[:space:]]") { exit }
			if ($0 ~ "^[[:space:]]+[A-Za-z0-9_.-]+:[[:space:]]*") {
				line=$0
				sub(/^[[:space:]]+/, "", line)
				key=line
				sub(/:.*/, "", key)
				value=line
				sub(/^[^:]+:[[:space:]]*/, "", value)
				gsub(/^"|"$/, "", value)
				gsub(/^'\''|'\''$/, "", value)
				gsub(/\r/, "", key)
				gsub(/\r/, "", value)
				print key "=" value
			}
		}
	' "$file"
}

file_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

list_stack_files() {
	local base="$1"
	find "$base" -type f -name '*.stack.yaml' | sort
}

existing_config_file_for_stack() {
	local stack_name="$1"
	aws codeconnections list-sync-configurations \
		--repository-link-id "${REPOSITORY_LINK_ID}" \
		--sync-type CFN_STACK_SYNC \
		--query "SyncConfigurations[?ResourceName=='${stack_name}'].ConfigFile" \
		--output text 2>/dev/null || true
}

stack_exists() {
	local stack_name="$1"
	aws cloudformation describe-stacks --stack-name "${stack_name}" >/dev/null 2>&1
}

stack_status() {
	local stack_name="$1"
	aws cloudformation describe-stacks \
		--stack-name "${stack_name}" \
		--query 'Stacks[0].StackStatus' \
		--output text 2>/dev/null || true
}

wait_for_stack_success() {
	local stack_name="$1"
	local max_checks=120
	local check=1
	local status

	while (( check <= max_checks )); do
		status="$(stack_status "${stack_name}")"

		case "${status}" in
			CREATE_COMPLETE|UPDATE_COMPLETE|IMPORT_COMPLETE)
				log "READY stack=${stack_name} status=${status}"
				return 0
				;;
			*_IN_PROGRESS|REVIEW_IN_PROGRESS|UPDATE_COMPLETE_CLEANUP_IN_PROGRESS|UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS)
				log "WAIT  stack=${stack_name} status=${status} check=${check}/${max_checks}"
				sleep 10
				check=$((check + 1))
				;;
			"")
				log "WAIT  stack=${stack_name} status=NOT_FOUND check=${check}/${max_checks}"
				sleep 10
				check=$((check + 1))
				;;
			*)
				log "ERROR stack=${stack_name} status=${status}"
				return 1
				;;
		esac
	done

	log "ERROR stack=${stack_name} timed out waiting for successful status"
	return 1
}

deploy_stack() {
	local stack_name="$1"
	local template_path="$2"
	local stack_file="$3"
	local -a param_overrides tag_overrides deploy_cmd

	if [[ -z "${template_path}" ]]; then
		log "SKIP  deploy stack=${stack_name} missing template-file-path"
		_LAST_ACTION="skipped"
		return 0
	fi

	if [[ ! -f "${REPO_ROOT}/${template_path}" ]]; then
		log "SKIP  deploy stack=${stack_name} template not found: ${template_path}"
		_LAST_ACTION="skipped"
		return 0
	fi

	local sha256_file="${REPO_ROOT}/${template_path%.*}.sha256.txt"
	local current_hash
	current_hash="$(file_sha256 "${REPO_ROOT}/${template_path}")"

	if stack_exists "${stack_name}" && [[ -f "${sha256_file}" ]]; then
		local stored_hash
		stored_hash="$(cat "${sha256_file}")"
		if [[ "${current_hash}" == "${stored_hash}" ]]; then
			log "SKIP  stack=${stack_name} template unchanged (sha256 match)"
			_LAST_ACTION="skipped"
			return 0
		fi
	fi

	while IFS= read -r kv; do
		[[ -n "${kv}" ]] && param_overrides+=("${kv}")
	done < <(yaml_section_key_values "${stack_file}" "parameters")

	while IFS= read -r kv; do
		[[ -n "${kv}" ]] && tag_overrides+=("${kv}")
	done < <(yaml_section_key_values "${stack_file}" "tags")

	if stack_exists "${stack_name}"; then
		log "UPDATE stack=${stack_name} template=${template_path}"
		_LAST_ACTION="updated"
	else
		log "CREATE stack=${stack_name} template=${template_path}"
		_LAST_ACTION="created"
	fi
	deploy_cmd=(
		aws cloudformation deploy
		--stack-name "${stack_name}"
		--template-file "${REPO_ROOT}/${template_path}"
		--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
		--no-fail-on-empty-changeset
	)

	if (( ${#param_overrides[@]} > 0 )); then
		deploy_cmd+=(--parameter-overrides "${param_overrides[@]}")
	fi

	if (( ${#tag_overrides[@]} > 0 )); then
		deploy_cmd+=(--tags "${tag_overrides[@]}")
	fi

	"${deploy_cmd[@]}" >/dev/null
	echo "${current_hash}" > "${sha256_file}"
	log "SHA256 stack=${stack_name} hash cached to ${template_path%.*}.sha256.txt"
}

create_sync_for_stack_file() {
	local file="$1"
	local tenant_id env_id root_name stack_name config_file template_path existing_cf
	_LAST_ACTION="skipped"

	tenant_id="$(yaml_value "$file" "TenantId")"
	env_id="$(yaml_value "$file" "EnvId")"

	if [[ -z "${tenant_id}" || -z "${env_id}" ]]; then
		log "SKIP  missing TenantId/EnvId in $(to_repo_relative_path "$file")"
		return 0
	fi

	root_name="$(stack_root_name "$file")"
	stack_name="${tenant_id}-${env_id}-${root_name}"
	config_file="$(to_repo_relative_path "$file")"
	template_path="$(yaml_value "$file" "template-file-path")"

	# Validate that the referenced template actually exists in the repo
	if [[ -z "${template_path}" ]]; then
		log "WARN  missing template-file-path in ${config_file}"
	elif [[ ! -f "${REPO_ROOT}/${template_path}" ]]; then
		log "WARN  template not found: ${template_path} (referenced by ${config_file})"
	fi

	deploy_stack "${stack_name}" "${template_path}" "${file}"

	if ! stack_exists "${stack_name}"; then
		log "ERROR stack=${stack_name} does not exist after bootstrap/validation"
		return 1
	fi

	wait_for_stack_success "${stack_name}"

	existing_cf="$(existing_config_file_for_stack "${stack_name}")"

	if [[ -z "${existing_cf}" || "${existing_cf}" == "None" ]]; then
		log "CREATE stack=${stack_name} config=${config_file}"
		aws codeconnections create-sync-configuration \
			--branch "${BRANCH}" \
			--config-file "${config_file}" \
			--repository-link-id "${REPOSITORY_LINK_ID}" \
			--resource-name "${stack_name}" \
			--role-arn "${ROLE_ARN}" \
			--sync-type CFN_STACK_SYNC \
			--publish-deployment-status ENABLED \
			--trigger-resource-update-on FILE_CHANGE \
			--pull-request-comment DISABLED \
			>/dev/null
	elif [[ "${existing_cf}" != "${config_file}" ]]; then
		log "UPDATE stack=${stack_name} old-config=${existing_cf} -> new-config=${config_file}"
		aws codeconnections update-sync-configuration \
			--resource-name "${stack_name}" \
			--sync-type CFN_STACK_SYNC \
			--branch "${BRANCH}" \
			--config-file "${config_file}" \
			--repository-link-id "${REPOSITORY_LINK_ID}" \
			--role-arn "${ROLE_ARN}" \
			>/dev/null
	else
		log "SKIP  stack=${stack_name} config=${config_file}"
	fi

	local final_status sha256_val
	final_status="$(stack_status "${stack_name}")"
	sha256_val="n/a"
	if [[ -n "${template_path}" && -f "${REPO_ROOT}/${template_path%.*}.sha256.txt" ]]; then
		sha256_val="$(cat "${REPO_ROOT}/${template_path%.*}.sha256.txt")"
		sha256_val="${sha256_val:0:12}"
	fi
	_SUMMARY+=("$(printf '%-55s  %-8s  %-22s  %s' "${stack_name}" "${_LAST_ACTION}" "${final_status}" "${sha256_val}")");
}

print_summary() {
	printf '\n'
	log "=== DEPLOY SUMMARY (${#_SUMMARY[@]} stacks) ==="
	printf '  %-55s  %-8s  %-22s  %s\n' "STACK" "ACTION" "STATUS" "SHA256"
	printf '  %-55s  %-8s  %-22s  %s\n' "-----" "------" "------" "------"
	local entry
	for entry in "${_SUMMARY[@]+${_SUMMARY[@]}}"; do
		printf '  %s\n' "${entry}"
	done
	printf '\n'
}

main() {
	load_repo_envrc
	parse_args "$@"
	require_cmd aws
	require_cmd find
	require_cmd sort
	require_cmd awk

	if [[ ! -d "${BASE_DIR}" ]]; then
		echo "ERROR: base directory not found: ${BASE_DIR}" >&2
		exit 1
	fi

	log "script [$0] started dir[${DIR}] base-dir[${BASE_DIR}] branch[${BRANCH}]"

	local total
	total="$(list_stack_files "${BASE_DIR}" | wc -l | tr -d ' ')"

	local count=0
	while IFS= read -r stack_file; do
		create_sync_for_stack_file "${stack_file}"
		count=$((count + 1))
		if (( count < total )); then
			log "SLEEP ${SLEEP_BETWEEN_STACKS_SECONDS}s before next stack"
			sleep "${SLEEP_BETWEEN_STACKS_SECONDS}"
		fi
	done < <(list_stack_files "${BASE_DIR}")

	log "processed stack files: ${count}"
	print_summary
	log "script [$0] completed"
}

main "$@"
