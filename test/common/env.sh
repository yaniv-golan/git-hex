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
		echo "ERROR: Cannot find mcp-bash framework. Set MCPBASH_HOME or install via the v0.8.2 installer (prefer --verify)." >&2
		exit 1
	fi
fi

export MCPBASH_PROJECT_ROOT="${PROJECT_ROOT}"
export PATH="${FRAMEWORK_DIR}/bin:${PATH}"

# Windows Git Bash/MSYS has relatively small exec argument limits (E2BIG).
# mcp-bash constructs registry JSON using jq/gojq --argjson with the full items array
# on the command line; forcing compact jq output keeps that payload small enough.
if [ -z "${MCPBASH_JSON_TOOL_BIN:-}" ]; then
	case "$(uname -s 2>/dev/null || printf '')" in
	MINGW* | MSYS* | CYGWIN*)
		if command -v jq >/dev/null 2>&1; then
			export MCPBASH_JSON_TOOL="jq"
			export MCPBASH_JSON_TOOL_BIN="${TEST_COMMON_DIR}/jq-compact.sh"
		fi
		;;
	esac
fi

# mcp-bash-framework v0.7.0+: tool execution is deny-by-default unless allowlisted.
# The allowlist is exact-match (no globs), so we set the full tool set explicitly.
# Callers can override (e.g., "*" in trusted projects).
if [ -z "${MCPBASH_TOOL_ALLOWLIST:-}" ]; then
	export MCPBASH_TOOL_ALLOWLIST="git-hex-getRebasePlan git-hex-checkRebaseConflicts git-hex-getConflictStatus git-hex-rebaseWithPlan git-hex-splitCommit git-hex-createFixup git-hex-amendLastCommit git-hex-cherryPickSingle git-hex-resolveConflict git-hex-continueOperation git-hex-abortOperation git-hex-undoLast"
fi

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
	# BSD/macOS `mktemp` requires an explicit template (or `-t`).
	TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/githex.test.XXXXXX")"
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
	stderr_file="$(mktemp "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/githex.stderr.XXXXXX")"

	# Framework sends diagnostics to stderr, stdout is clean JSON (may be multiple lines)
	# Capture stderr to a temp file for debugging on failure
	# In CI mode, add --verbose to stream tool stderr for better debugging
	local verbose_flag=""
	if [ "${MCPBASH_CI_MODE:-}" = "1" ] || [ "${MCPBASH_CI_VERBOSE:-}" = "1" ]; then
		verbose_flag="--verbose"
	fi
	# shellcheck disable=SC2086
	raw_output="$(mcp-bash run-tool "${tool_name}" \
		--project-root "${MCPBASH_PROJECT_ROOT}" \
		--roots "${roots}" \
		--args "${args_json}" \
		--timeout "${timeout}" ${verbose_flag} 2>"${stderr_file}")" || true

	local jq_status=0
	local error_obj=""
	local structured=""
	# Single jq pass:
	# - If an MCP tool error exists, emit that error object and exit non-zero.
	# - Otherwise, emit the first structuredContent payload (or empty).
	set +e
	structured="$(printf '%s' "${raw_output}" | jq -s -c '
		(map(select(._mcpToolError == true)) | .[0] // null) as $err
		| if $err != null then
			($err), halt_error(1)
		else
			(map(select(.structuredContent)) | .[0].structuredContent // empty)
		end
	' 2>/dev/null)"
	jq_status=$?
	set -e

	if [ "${jq_status}" -ne 0 ] && [ -n "${structured}" ]; then
		error_obj="${structured}"
		structured=""
	fi

	# If any line is an error response (framework may emit notifications first)
	if [ -n "${error_obj}" ]; then
		# Print stderr for debugging
		if [ -s "${stderr_file}" ]; then
			printf '[run_tool %s] stderr:\n' "${tool_name}" >&2
			cat "${stderr_file}" >&2
		fi
		printf '[run_tool %s] error: %s\n' "${tool_name}" "${error_obj}" >&2
		rm -f "${stderr_file}"
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

	if [ -z "${structured}" ]; then
		# Fallback: maybe it's the raw output format (or jq failed to parse output)
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
