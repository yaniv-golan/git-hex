#!/usr/bin/env bash
# Test environment setup for git-hex

set -euo pipefail

# Detect script location and project root
TEST_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEST_DIR="$(dirname "${TEST_COMMON_DIR}")"
PROJECT_ROOT="$(dirname "${TEST_DIR}")"

# Framework location - prefer explicit env, then sibling checkout, then XDG default
if [ -n "${MCPBASH_HOME:-}" ]; then
	FRAMEWORK_DIR="${MCPBASH_HOME}"
elif [ -d "${PROJECT_ROOT}/../mcpbash" ]; then
	# Local development: git-hex and mcpbash are sibling directories
	FRAMEWORK_DIR="${PROJECT_ROOT}/../mcpbash"
else
	XDG_FRAMEWORK_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/mcp-bash"
	if [ -d "${XDG_FRAMEWORK_DIR}" ]; then
		FRAMEWORK_DIR="${XDG_FRAMEWORK_DIR}"
	else
		echo "ERROR: Cannot find mcp-bash framework. Set MCPBASH_HOME or install via the v0.6.0 installer." >&2
		exit 1
	fi
fi

export MCPBASH_PROJECT_ROOT="${PROJECT_ROOT}"
export PATH="${FRAMEWORK_DIR}/bin:${PATH}"

# Prefer CI-safe defaults when running under automation
if [ "${CI:-}" = "true" ] && [ -z "${MCPBASH_CI_MODE:-}" ]; then
	export MCPBASH_CI_MODE=1
fi
if [ -n "${MCPBASH_TRACE_TOOLS:-}" ] && [ -z "${MCPBASH_TRACE_PS4:-}" ]; then
	# shellcheck disable=SC2016 # Single quotes intentional - PS4 expands at runtime in the tool
	export MCPBASH_TRACE_PS4='+${BASH_SOURCE}:${LINENO}: '
fi

# Create temp directory for test artifacts
test_create_tmpdir() {
	TEST_TMPDIR="$(mktemp -d)"
	export TEST_TMPDIR
	trap 'rm -rf "${TEST_TMPDIR}"' EXIT
}

# Verify framework is available
test_verify_framework() {
	if ! command -v mcp-bash >/dev/null 2>&1; then
		echo "ERROR: mcp-bash not found in PATH" >&2
		exit 1
	fi
}

# Run a tool and extract the structured content from the response
# Usage: run_tool <tool-name> <roots> <args-json> [timeout]
# Returns: The structuredContent JSON on stdout, or error JSON if tool failed
# Note: stderr is captured and printed on failure for debugging
run_tool() {
	local tool_name="$1"
	local roots="$2"
	local args_json="$3"
	local timeout="${4:-30}"

	local raw_output stderr_file
	stderr_file="$(mktemp)"

	# Framework sends diagnostics to stderr, stdout is clean JSON (may be multiple lines)
	# Capture stderr to a temp file for debugging on failure
	raw_output="$(mcp-bash run-tool "${tool_name}" \
		--project-root "${MCPBASH_PROJECT_ROOT}" \
		--roots "${roots}" \
		--args "${args_json}" \
		--timeout "${timeout}" 2>"${stderr_file}")" || true

	# Check if any line is an error response (framework may emit notifications first)
	if echo "${raw_output}" | jq -es 'map(select(._mcpToolError == true)) | length > 0' >/dev/null 2>&1; then
		# Print stderr for debugging
		if [ -s "${stderr_file}" ]; then
			printf '[run_tool %s] stderr:\n' "${tool_name}" >&2
			cat "${stderr_file}" >&2
		fi
		# Print the error object for debugging
		local error_obj
		error_obj="$(echo "${raw_output}" | jq -s 'map(select(._mcpToolError == true)) | .[0]')"
		printf '[run_tool %s] error: %s\n' "${tool_name}" "${error_obj}" >&2
		rm -f "${stderr_file}"
		# Return the error object
		echo "${error_obj}"
		return 1
	fi

	# Check if output is empty (tool may have crashed)
	if [ -z "${raw_output}" ]; then
		printf '[run_tool %s] ERROR: No output from tool\n' "${tool_name}" >&2
		if [ -s "${stderr_file}" ]; then
			printf '[run_tool %s] stderr:\n' "${tool_name}" >&2
			cat "${stderr_file}" >&2
		fi
		rm -f "${stderr_file}"
		return 1
	fi

	# Always print stderr for debugging in CI
	if [ -s "${stderr_file}" ]; then
		printf '[run_tool %s] stderr:\n' "${tool_name}" >&2
		cat "${stderr_file}" >&2
	fi
	rm -f "${stderr_file}"

	# Extract structuredContent from the result line (skip notifications)
	local structured
	structured="$(echo "${raw_output}" | jq -s 'map(select(.structuredContent)) | .[0].structuredContent // empty' 2>/dev/null || echo "${raw_output}")"
	if [ -z "${structured}" ]; then
		# Fallback: maybe it's the raw output format
		structured="${raw_output}"
	fi

	# Debug: show raw output if structured content extraction failed
	if [ -z "${structured}" ] || [ "${structured}" = "null" ]; then
		printf '[run_tool %s] WARNING: No structuredContent found\n' "${tool_name}" >&2
		printf '[run_tool %s] raw_output: %s\n' "${tool_name}" "${raw_output}" >&2
	fi

	echo "${structured}"
}

# Run a tool expecting it to fail
# Usage: run_tool_expect_fail <tool-name> <roots> <args-json>
# Returns: 0 if tool failed (as expected), 1 if tool succeeded
run_tool_expect_fail() {
	local tool_name="$1"
	local roots="$2"
	local args_json="$3"

	if run_tool "${tool_name}" "${roots}" "${args_json}" >/dev/null 2>&1; then
		return 1 # Tool succeeded when we expected failure
	fi
	return 0 # Tool failed as expected
}
