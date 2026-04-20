#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"
REPO_ROOT="$(cd "${DIR}/.." && pwd)"

# shellcheck source=aws-lib.sh
source "${DIR}/aws-lib.sh"

BRANCH="${GIT_SYNC_BRANCH:-main}"
REPOSITORY_LINK_ID="${REPOSITORY_LINK_ID:-}"
ROLE_ARN="${GIT_SYNC_ROLE_ARN:-}"
CLOUDFRONT_DISTRIBUTION_IDS="${CLOUDFRONT_DISTRIBUTION_IDS:-}"
CLOUDFRONT_INVALIDATION_PATHS="${CLOUDFRONT_INVALIDATION_PATHS:-/*}"
SLEEP_BETWEEN_STACKS=2
_SUMMARY=()

# ─────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────

combined_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		for f in "$@"; do
			cat "$f"
			printf '\n'
		done | sha256sum | awk '{print $1}'
	else
		for f in "$@"; do
			cat "$f"
			printf '\n'
		done | shasum -a 256 | awk '{print $1}'
	fi
}

stack_sha_file() {
	local stack_file="$1"
	printf '%s\n' "${stack_file%.stack.yaml}.stack.sha256.txt"
}

stack_status() {
	aws cloudformation describe-stacks \
		--stack-name "$1" \
		--query 'Stacks[0].StackStatus' \
		--output text 2>/dev/null || true
}

# Parse key=value pairs from a named YAML section (parameters/tags)
yaml_section() {
	local file="$1" section="$2"
	awk -v s="${section}" '
		$0 ~ "^[[:space:]]*" s ":[[:space:]]*$" { in_s=1; next }
		in_s {
			if ($0 ~ "^[^[:space:]]") exit
			if ($0 ~ "^[[:space:]]+[A-Za-z0-9_.-]+:[[:space:]]*") {
				line=$0; sub(/^[[:space:]]+/,"",line)
				k=line; sub(/:.*$/,"",k)
				v=line; sub(/^[^:]+:[[:space:]]*/,"",v)
				gsub(/^"|"$|^'"'"'|'"'"'$/,"",v)
				gsub(/\r/,"",k); gsub(/\r/,"",v)
				print k "=" v
			}
		}
	' "${file}"
}

# ─────────────────────────────────────────────────────────────────
# Wait for CFN stack to reach a terminal success state
# ─────────────────────────────────────────────────────────────────

wait_for_stack() {
	local stack="$1" n=1 max=120 status
	while (( n <= max )); do
		status="$(stack_status "${stack}")"
		case "${status}" in
			CREATE_COMPLETE|UPDATE_COMPLETE|IMPORT_COMPLETE|UPDATE_ROLLBACK_COMPLETE)
				log "READY ${stack} (${status})"
				return 0
				;;
			*_IN_PROGRESS|REVIEW_IN_PROGRESS)
				log "WAIT  ${stack} (${status}) ${n}/${max}"
				sleep 10
				(( n++ )) || true
				;;
			*)
				log "ERROR ${stack} (${status:-NOT_FOUND})"
				return 1
				;;
		esac
	done
	log "ERROR ${stack} timed out after $((max * 10))s"
	return 1
}

# ─────────────────────────────────────────────────────────────────
# Deploy one CFN stack from a template + stack file.
# Prints action to stdout: created | updated | skipped
# All log output goes to stderr (via log()).
# ─────────────────────────────────────────────────────────────────

deploy_stack() {
	local stack_name="$1" template_path="$2" stack_file="$3"

	if [[ -z "${template_path}" || ! -f "${REPO_ROOT}/${template_path}" ]]; then
		log "SKIP  ${stack_name} (template not found: ${template_path:-<none>})"
		echo "skipped"
		return 0
	fi

	local sha_file="$(stack_sha_file "${stack_file}")"
	local current_hash
	current_hash="$(combined_sha256 "${stack_file}" "${REPO_ROOT}/${template_path}")"

	# Handle stuck states before checking sha cache
	local status
	status="$(stack_status "${stack_name}")"

	if [[ "${status}" == "DELETE_IN_PROGRESS" ]]; then
		log "WAIT  ${stack_name} (DELETE_IN_PROGRESS)"
		while [[ "$(stack_status "${stack_name}")" == "DELETE_IN_PROGRESS" ]]; do sleep 5; done
		status="$(stack_status "${stack_name}")"
	fi

	if [[ "${status}" == "ROLLBACK_COMPLETE" ]]; then
		log "DELETE ${stack_name} (ROLLBACK_COMPLETE — deleting before redeploy)"
		aws cloudformation delete-stack --stack-name "${stack_name}"
		while [[ -n "$(stack_status "${stack_name}")" ]]; do sleep 5; done
		rm -f "${sha_file}"
		status=""
	fi

	# Clear sha cache if stack no longer exists
	if [[ -z "${status}" || "${status}" == "DELETE_COMPLETE" ]]; then
		rm -f "${sha_file}"
	fi

	# If the stack exists but the sha cache is missing, force a redeploy so the
	# cache file is recreated from the current stack descriptor + template in git.
	if [[ -n "${status}" && "${status}" != "DELETE_COMPLETE" && ! -f "${sha_file}" ]]; then
		log "REDEPLOY ${stack_name} (sha256 cache missing → ${status})"
	fi

	# Skip if template unchanged and stack is live
	if [[ -n "${status}" && "${status}" != "DELETE_COMPLETE" && -f "${sha_file}" ]]; then
		if [[ "${current_hash}" == "$(cat "${sha_file}")" ]]; then
			log "SKIP  ${stack_name} (sha256 match → ${status})"
			echo "skipped"
			return 0
		fi
	fi

	# Build parameter and tag arrays, expanding ${VAR} tokens in param values
	local -a params=() tags=()
	local kv k v
	while IFS= read -r kv; do
		[[ -z "${kv}" ]] && continue
		k="${kv%%=*}"; v="${kv#*=}"
		if [[ "${v}" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
			local _vn="${BASH_REMATCH[1]}"
			v="${!_vn:-${v}}"
		fi
		params+=("${k}=${v}")
	done < <(yaml_section "${stack_file}" "parameters")

	while IFS= read -r kv; do
		[[ -n "${kv}" ]] && tags+=("${kv}")
	done < <(yaml_section "${stack_file}" "tags")

	local action="created"
	[[ -n "${status}" && "${status}" != "DELETE_COMPLETE" ]] && action="updated"
	log "$(echo "${action}" | tr '[:lower:]' '[:upper:]') ${stack_name}"

	local -a cmd=(
		aws cloudformation deploy
		--stack-name "${stack_name}"
		--template-file "${REPO_ROOT}/${template_path}"
		--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
		--no-fail-on-empty-changeset
	)
	(( ${#params[@]} > 0 )) && cmd+=(--parameter-overrides "${params[@]}")
	(( ${#tags[@]} > 0 ))   && cmd+=(--tags "${tags[@]}")

	"${cmd[@]}" >/dev/null
	printf '%s\n' "${current_hash}" > "${sha_file}"
	echo "${action}"
}

# ─────────────────────────────────────────────────────────────────
# Ensure a CodeConnections sync config exists for the stack
# ─────────────────────────────────────────────────────────────────

ensure_sync_config() {
	local stack="$1" config_file="$2"
	local existing
	existing="$(aws codeconnections get-sync-configuration \
		--resource-name "${stack}" \
		--sync-type CFN_STACK_SYNC \
		--query 'SyncConfiguration.ConfigFile' \
		--output text 2>/dev/null || true)"

	if [[ -z "${existing}" || "${existing}" == "None" ]]; then
		log "SYNC  CREATE ${stack} (${config_file})"
		aws codeconnections create-sync-configuration \
			--branch "${BRANCH}" \
			--config-file "${config_file}" \
			--repository-link-id "${REPOSITORY_LINK_ID}" \
			--resource-name "${stack}" \
			--role-arn "${ROLE_ARN}" \
			--sync-type CFN_STACK_SYNC \
			--publish-deployment-status ENABLED \
			--trigger-resource-update-on FILE_CHANGE \
			--pull-request-comment DISABLED \
			>/dev/null
	elif [[ "${existing}" != "${config_file}" ]]; then
		log "SYNC  UPDATE ${stack} (${existing} → ${config_file})"
		aws codeconnections update-sync-configuration \
			--resource-name "${stack}" \
			--sync-type CFN_STACK_SYNC \
			--branch "${BRANCH}" \
			--config-file "${config_file}" \
			--repository-link-id "${REPOSITORY_LINK_ID}" \
			--role-arn "${ROLE_ARN}" \
			>/dev/null
	else
		log "SYNC  SKIP ${stack} (${config_file})"
	fi
}

# ─────────────────────────────────────────────────────────────────
# Optionally invalidate CloudFront distributions after deploy
# ─────────────────────────────────────────────────────────────────

invalidate_distributions() {
	local ids="${CLOUDFRONT_DISTRIBUTION_IDS//,/ }"
	[[ -z "${ids// /}" ]] && {
		log "CFINV SKIP (CLOUDFRONT_DISTRIBUTION_IDS not set)"
		return 0
	}

	local -a paths=()
	read -r -a paths <<< "${CLOUDFRONT_INVALIDATION_PATHS}"
	(( ${#paths[@]} > 0 )) || paths=("/*")

	local dist inv_id
	for dist in ${ids}; do
		[[ -z "${dist}" ]] && continue
		log "CFINV CREATE ${dist} (paths: ${paths[*]})"
		inv_id="$(aws cloudfront create-invalidation \
			--distribution-id "${dist}" \
			--paths "${paths[@]}" \
			--query 'Invalidation.Id' \
			--output text)"
		log "CFINV READY ${dist} (id: ${inv_id})"
	done
}

# ─────────────────────────────────────────────────────────────────
# Process one *.stack.yaml file
# ─────────────────────────────────────────────────────────────────

process_stack_file() {
	local file="$1"
	local rel_path="${file#${REPO_ROOT}/}"

	local tenant_id
	tenant_id="$(yaml_value "${file}" "TenantId")"

	if [[ -z "${tenant_id}" ]]; then
		log "SKIP  ${rel_path} (missing TenantId)"
		return 0
	fi

	local stack_name template_path hook_base
	stack_name="$(stack_name_from_file "${file}")"
	template_path="$(yaml_value "${file}" "template-file-path")"
	hook_base="${file%.stack.yaml}"

	if [[ -f "${hook_base}.before.sh" ]]; then
		log "HOOK  before ${stack_name}"
		bash "${hook_base}.before.sh" "${stack_name}" "${file}" || {
			log "FATAL  ${stack_name}: before hook failed (exit $?)"
			exit 1
		}
	fi

	local action
	action="$(deploy_stack "${stack_name}" "${template_path}" "${file}")" || {
		log "FATAL  ${stack_name}: deploy failed"
		exit 1
	}
	wait_for_stack "${stack_name}" || {
		log "FATAL  ${stack_name}: stack did not reach a ready state"
		exit 1
	}
	ensure_sync_config "${stack_name}" "${rel_path}"

	if [[ -f "${hook_base}.after.sh" ]]; then
		log "HOOK  after ${stack_name}"
		bash "${hook_base}.after.sh" "${stack_name}" "${file}" || {
			log "FATAL  ${stack_name}: after hook failed (exit $?)"
			exit 1
		}
	fi

	local status sha_short="n/a"
	status="$(stack_status "${stack_name}")"
	local sha_file
	sha_file="$(stack_sha_file "${file}")"
	if [[ -f "${sha_file}" ]]; then
		sha_short="$(cut -c1-12 "${sha_file}")"
	fi
	_SUMMARY+=("$(printf '%-55s  %-8s  %-22s  %s' "${stack_name}" "${action}" "${status}" "${sha_short}")")
}

# ─────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────

load_envrc() {
	local envrc="${REPO_ROOT}/.envrc"
	[[ -f "${envrc}" ]] || return 0
	log "Loading ${envrc}"
	set +u
	# shellcheck disable=SC1090
	source "${envrc}"
	set -u
	BRANCH="${GIT_SYNC_BRANCH:-main}"
	REPOSITORY_LINK_ID="${REPOSITORY_LINK_ID:-}"
	ROLE_ARN="${GIT_SYNC_ROLE_ARN:-}"
	CLOUDFRONT_DISTRIBUTION_IDS="${CLOUDFRONT_DISTRIBUTION_IDS:-}"
	CLOUDFRONT_INVALIDATION_PATHS="${CLOUDFRONT_INVALIDATION_PATHS:-/*}"
}

main() {
	load_envrc

	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		echo "Usage: $0 [-h|--help]"
		echo "  Deploys all *.stack.yaml files under git-sync/ in sorted order."
		echo "  Env: REPOSITORY_LINK_ID, GIT_SYNC_ROLE_ARN, GIT_SYNC_BRANCH"
		echo "       CLOUDFRONT_DISTRIBUTION_IDS (optional, comma/space-separated)"
		echo "       CLOUDFRONT_INVALIDATION_PATHS (optional, default: /*)"
		exit 0
	fi

	if [[ -z "${REPOSITORY_LINK_ID}" || -z "${ROLE_ARN}" || -z "${BRANCH}" ]]; then
		echo "ERROR: REPOSITORY_LINK_ID, GIT_SYNC_ROLE_ARN, GIT_SYNC_BRANCH not set" >&2
		exit 1
	fi

	for cmd in aws find awk; do
		command -v "${cmd}" >/dev/null 2>&1 || { echo "ERROR: ${cmd} not found" >&2; exit 1; }
	done

	log "deploy started branch=${BRANCH}"

	local -a files=()
	while IFS= read -r f; do files+=("${f}"); done \
		< <(find "${DIR}" -name '*.stack.yaml' -type f | sort)

	local n=0 total="${#files[@]}"
	for f in "${files[@]}"; do
		(( n++ )) || true
		log "── stack ${n}/${total}: ${f#${REPO_ROOT}/}"
		process_stack_file "${f}"
		(( n < total )) && sleep "${SLEEP_BETWEEN_STACKS}"
	done

	log "=== SUMMARY (${#_SUMMARY[@]} stacks) ==="
	printf '  %-55s  %-8s  %-22s  %s\n' "STACK" "ACTION" "STATUS" "SHA256"
	printf '  %-55s  %-8s  %-22s  %s\n' "─────" "──────" "──────" "──────"
	printf '  %s\n' "${_SUMMARY[@]+"${_SUMMARY[@]}"}"
	invalidate_distributions
	log "deploy done"
}

main "$@"
