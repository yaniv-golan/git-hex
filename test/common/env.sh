#!/usr/bin/env bash
# Test environment setup for git-hex

set -euo pipefail

# Detect script location and project root
TEST_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(dirname "${TEST_COMMON_DIR}")"
PROJECT_ROOT="$(dirname "${TEST_DIR}")"

# Framework location - prefer local development version, then installed version
if [ -n "${MCPBASH_HOME:-}" ]; then
	FRAMEWORK_DIR="${MCPBASH_HOME}"
elif [ -d "${PROJECT_ROOT}/../mcpbash" ]; then
	# Local development: git-hex and mcpbash are sibling directories
	FRAMEWORK_DIR="${PROJECT_ROOT}/../mcpbash"
elif [ -d "${HOME}/mcp-bash-framework" ]; then
	FRAMEWORK_DIR="${HOME}/mcp-bash-framework"
else
	echo "ERROR: Cannot find mcp-bash framework. Set MCPBASH_HOME or install to ~/mcp-bash-framework" >&2
	exit 1
fi

export MCPBASH_PROJECT_ROOT="${PROJECT_ROOT}"
export PATH="${FRAMEWORK_DIR}/bin:${PATH}"

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
run_tool() {
	local tool_name="$1"
	local roots="$2"
	local args_json="$3"
	local timeout="${4:-30}"
	
	local raw_output
	# Framework sends diagnostics to stderr, stdout is clean JSON
	raw_output="$(mcp-bash run-tool "${tool_name}" \
		--project-root "${MCPBASH_PROJECT_ROOT}" \
		--roots "${roots}" \
		--args "${args_json}" \
		--timeout "${timeout}" 2>/dev/null)"
	
	# Check if it's an error response
	if echo "${raw_output}" | jq -e '._mcpToolError == true' >/dev/null 2>&1; then
		# Return the error as-is
		echo "${raw_output}"
		return 1
	fi
	
	# Extract structuredContent (handle case where it might be the raw output)
	local structured
	structured="$(echo "${raw_output}" | jq -r '.structuredContent // .' 2>/dev/null || echo "${raw_output}")"
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
		return 1  # Tool succeeded when we expected failure
	fi
	return 0  # Tool failed as expected
}
