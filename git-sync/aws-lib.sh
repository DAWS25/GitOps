# aws-lib.sh — shared functions sourced by aws-deploy.sh and aws-gc.sh
# Source this file; do not execute directly.

log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Extract a scalar value from a simple YAML file
yaml_value() {
	local file="$1" key="$2"
	awk -F: -v k="$key" '
		$1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
			sub(/^[[:space:]]+/, "", $2); sub(/[[:space:]]+$/, "", $2)
			gsub(/^"|"$|^'"'"'|'"'"'$/, "", $2)
			gsub(/\r/, "", $2)
			print $2; exit
		}
	' "$file"
}

# Derive a stack root name from a *.stack.yaml file path.
# Strips all purely-numeric dash-separated segments.
# e.g. 010-source-credentials.stack.yaml -> source-credentials
# e.g. vpc-3rnat-00-vpc.stack.yaml       -> vpc-3rnat-vpc
stack_root_name() {
	local file="$1"
	local base name result segment
	base="$(basename "${file}")"
	name="${base%%.*}"
	result=""
	IFS='-' read -ra _parts <<< "${name}"
	for segment in "${_parts[@]}"; do
		if [[ "${segment}" =~ ^[0-9]+$ ]]; then
			continue
		fi
		result="${result:+${result}-}${segment}"
	done
	echo "${result}"
}

# Derive the full stack name from a *.stack.yaml file path.
stack_name_from_file() {
	local file="$1"
	local tenant_id env_id root_name
	tenant_id="$(yaml_value "${file}" "TenantId")"
	env_id="$(yaml_value "${file}" "EnvId")"
	root_name="$(stack_root_name "${file}")"
	echo "${tenant_id}-${env_id}-${root_name}"
}
