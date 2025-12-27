#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v jq >/dev/null 2>&1; then
	echo "ERROR: jq is required for schema checks" >&2
	exit 2
fi

failures=0

fail() {
	echo "ERROR: $*" >&2
	failures=$((failures + 1))
}

assert_jq() {
	local file="$1"
	local expr="$2"
	local message="$3"
	if ! jq -e "${expr}" "${file}" >/dev/null 2>&1; then
		fail "${file}: ${message}"
	fi
}

assert_required_for_output_objects() {
	local file="$1"
	# For any outputSchema subtree object with properties, require an explicit required list.
	# shellcheck disable=SC2016
	jq -r '
		def paths_missing_required:
			path(.. | objects | select((.type? == "object") and (has("properties")) and (has("required") | not)));
		(.outputSchema // {}) as $o
		| ($o | paths_missing_required) as $paths
		| if ($paths | length) == 0 then empty else $paths[] | @json end
	' "${file}" | while IFS= read -r path_json; do
		[ -n "${path_json}" ] || continue
		fail "${file}: outputSchema has object with properties but no required at path ${path_json}"
	done
}

assert_operation_type_enum() {
	local file="$1"
	# If any property is named operationType in outputSchema, enforce enum.
	# shellcheck disable=SC2016
	if jq -e '(.outputSchema // {}) | .. | objects | select(has("properties") and (.properties.operationType? != null) and (.properties.operationType.enum? == null))' "${file}" >/dev/null 2>&1; then
		fail "${file}: outputSchema.properties.operationType is missing enum"
	fi
}

while IFS= read -r meta; do
	[ -n "${meta}" ] || continue
	dir="$(dirname "${meta}")"
	dir_base="$(basename "${dir}")"

	assert_jq "${meta}" '.' "invalid JSON"
	assert_jq "${meta}" '(.name? | type) == "string" and (.name | length > 0)' "missing/invalid .name"
	assert_jq "${meta}" '(.description? | type) == "string" and (.description | length > 0)' "missing/invalid .description"
	assert_jq "${meta}" '(.inputSchema.type? == "object")' "inputSchema.type must be object"
	assert_jq "${meta}" '(.outputSchema.type? == "object")' "outputSchema.type must be object"
	assert_jq "${meta}" '(.outputSchema.required? | type) == "array"' "outputSchema.required must be an array"
	assert_jq "${meta}" '(.outputSchema.required | index("success") != null)' "outputSchema.required must include \"success\""

	# Ensure .name matches directory (tools/git-hex-foo/tool.meta.json => name=git-hex-foo)
	if ! jq -e --arg expected "${dir_base}" '.name == $expected' "${meta}" >/dev/null 2>&1; then
		fail "${meta}: tool name does not match directory name (${dir_base})"
	fi

	assert_required_for_output_objects "${meta}"
	assert_operation_type_enum "${meta}"
done < <(find "${ROOT_DIR}/tools" -mindepth 2 -maxdepth 2 -name 'tool.meta.json' | sort)

if [ "${failures}" -ne 0 ]; then
	exit 1
fi
