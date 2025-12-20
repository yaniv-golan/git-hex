#!/usr/bin/env bash
# Test assertion helpers for git-hex

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

_test_json_bin() {
	if [ -n "${TEST_JSON_TOOL_BIN:-}" ] && command -v "${TEST_JSON_TOOL_BIN}" >/dev/null 2>&1; then
		printf '%s\n' "${TEST_JSON_TOOL_BIN}"
		return 0
	fi
	if [ -n "${MCPBASH_JSON_TOOL_BIN:-}" ] && command -v "${MCPBASH_JSON_TOOL_BIN}" >/dev/null 2>&1; then
		printf '%s\n' "${MCPBASH_JSON_TOOL_BIN}"
		return 0
	fi
	printf '%s\n' "jq"
}

test_require_command() {
	local cmd="$1"
	if ! command -v "${cmd}" >/dev/null 2>&1; then
		test_fail "Required command not found: ${cmd}"
	fi
}

test_fail() {
	local message="$1"
	printf "${RED}FAIL${NC}: %s\n" "${message}" >&2
	exit 1
}

test_pass() {
	local message="$1"
	printf "${GREEN}PASS${NC}: %s\n" "${message}"
}

assert_eq() {
	local expected="$1"
	local actual="$2"
	local message="${3:-Values should be equal}"

	if [ "${expected}" != "${actual}" ]; then
		test_fail "${message} (expected: '${expected}', got: '${actual}')"
	fi
}

assert_ne() {
	local unexpected="$1"
	local actual="$2"
	local message="${3:-Values should not be equal}"

	if [ "${unexpected}" = "${actual}" ]; then
		test_fail "${message} (got unexpected value: '${actual}')"
	fi
}

assert_contains() {
	local haystack="$1"
	local needle="$2"
	local message="${3:-String should contain substring}"

	if [[ "${haystack}" != *"${needle}"* ]]; then
		test_fail "${message} (looking for '${needle}' in '${haystack}')"
	fi
}

run_tool_expect_fail_message_contains() {
	local tool_name="$1"
	local roots="$2"
	local args_json="$3"
	local needle="$4"
	local message="${5:-Tool should fail with expected message}"

	local out status tool_msg
	set +e
	out="$(run_tool "${tool_name}" "${roots}" "${args_json}" 2>/dev/null)"
	status=$?
	set -e

	if [ "${status}" -eq 0 ]; then
		test_fail "${message} (tool succeeded unexpectedly)"
	fi

	tool_msg="$(printf '%s' "${out}" | "$(_test_json_bin)" -r '.message // empty' 2>/dev/null || echo "")"
	if [ -z "${tool_msg}" ]; then
		test_fail "${message} (no error message found)"
	fi
	assert_contains "${tool_msg}" "${needle}" "${message}"
}

assert_file_exists() {
	local path="$1"
	local message="${2:-File should exist}"

	if [ ! -f "${path}" ]; then
		test_fail "${message}: ${path}"
	fi
}

assert_dir_exists() {
	local path="$1"
	local message="${2:-Directory should exist}"

	if [ ! -d "${path}" ]; then
		test_fail "${message}: ${path}"
	fi
}

assert_json_field() {
	local json="$1"
	local field="$2"
	local expected="$3"
	local message="${4:-JSON field should match}"

	local actual
	actual="$(printf '%s' "${json}" | "$(_test_json_bin)" -r "${field}" 2>/dev/null || echo "")"

	if [ "${expected}" != "${actual}" ]; then
		test_fail "${message} (field ${field}: expected '${expected}', got '${actual}')"
	fi
}

# Assert multiple JSON fields with a single jq invocation.
# Usage: assert_json_fields_eq "$json" ".success" "true" ".undoneOperation" "amendLastCommit" ...
assert_json_fields_eq() {
	local json="$1"
	shift
	if [ $(($# % 2)) -ne 0 ]; then
		test_fail "assert_json_fields_eq requires field/expected pairs"
	fi

	local -a fields expecteds
	while [ "$#" -gt 0 ]; do
		fields+=("$1")
		expecteds+=("$2")
		shift 2
	done

	local jq_filter values
	jq_filter='['
	local field
	for field in "${fields[@]}"; do
		jq_filter+="(${field}),"
	done
	# Use a delimiter that won't collide with JSON strings containing tabs/spaces.
	jq_filter="${jq_filter%,}] | map(if . == null then \"\" else tostring end) | join(\"\\u001f\")"

	values="$(printf '%s' "${json}" | "$(_test_json_bin)" -r "${jq_filter}" 2>/dev/null || true)"
	if [ -z "${values}" ]; then
		test_fail "assert_json_fields_eq could not extract fields"
	fi

	local -a actuals
	IFS=$'\x1f' read -r -a actuals <<<"${values}"

	local i
	for i in "${!expecteds[@]}"; do
		if [ "${expecteds[$i]}" != "${actuals[$i]:-}" ]; then
			test_fail "JSON field mismatch at index ${i} (expected: '${expecteds[$i]}', got: '${actuals[$i]:-}')"
		fi
	done
}
