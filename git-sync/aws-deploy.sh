#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"
REPO_ROOT="$(cd "${DIR}/.." && pwd)"

BASE_DIR="${DIR}"
BRANCH="${GIT_SYNC_BRANCH:-main}"
REPOSITORY_LINK_ID="${REPOSITORY_LINK_ID:-}"
ROLE_ARN="${GIT_SYNC_ROLE_ARN:-}"
DRY_RUN=0

log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

usage() {
	cat <<'EOF'
Usage: git-sync/aws-deploy.sh --repository-link-id <id> --role-arn <arn> [options]

Options:
	--repository-link-id <id>   Required. CodeConnections repository link ID.
	--role-arn <arn>            Required. IAM role ARN used by Git sync.
	--branch <name>             Branch to sync from. Default: main.
	--base-dir <path>           Directory to scan recursively. Default: git-sync/.
	--dry-run                   Print actions without calling AWS APIs.
	-h, --help                  Show this help.

Behavior:
	- Finds all *.stack.yaml files recursively under --base-dir in name order.
	- Extracts TenantId and EnvId from each YAML file.
	- Computes RootName as the filename prefix before the first dot.
	- Builds stack name as TenantId-EnvId-RootName.
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
			--repository-link-id)
				REPOSITORY_LINK_ID="${2:-}"
				shift 2
				;;
			--role-arn)
				ROLE_ARN="${2:-}"
				shift 2
				;;
			--branch)
				BRANCH="${2:-}"
				shift 2
				;;
			--base-dir)
				BASE_DIR="${2:-}"
				shift 2
				;;
			--dry-run)
				DRY_RUN=1
				shift
				;;
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

	if [[ -z "${REPOSITORY_LINK_ID}" || -z "${ROLE_ARN}" ]]; then
		echo "ERROR: --repository-link-id and --role-arn are required." >&2
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
			print $2
			exit
		}
	' "$file"
}

list_stack_files() {
	local base="$1"
	find "$base" -type f -name '*.stack.yaml' | sort
}

sync_exists_for_stack() {
	local stack_name="$1"
	local existing
	existing=$(aws codeconnections list-sync-configurations \
		--repository-link-id "${REPOSITORY_LINK_ID}" \
		--sync-type CFN_STACK_SYNC \
		--query "SyncConfigurations[?ResourceName=='${stack_name}'].ResourceName" \
		--output text 2>/dev/null || true)
	[[ -n "${existing}" && "${existing}" != "None" ]]
}

create_sync_for_stack_file() {
	local file="$1"
	local tenant_id env_id root_name stack_name config_file template_path

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

	if sync_exists_for_stack "${stack_name}"; then
		log "SKIP  sync exists stack=${stack_name} template=${template_path}"
		return 0
	fi

	log "CREATE sync stack=${stack_name} template=${template_path}"
	if (( DRY_RUN == 1 )); then
		return 0
	fi

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
}

main() {
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

	local count=0
	while IFS= read -r stack_file; do
		create_sync_for_stack_file "${stack_file}"
		count=$((count + 1))
	done < <(list_stack_files "${BASE_DIR}")

	log "processed stack files: ${count}"
	log "script [$0] completed"
}

main "$@"
