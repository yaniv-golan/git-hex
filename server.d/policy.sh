#!/usr/bin/env bash
# Tool execution policy for git-hex
#
# Adds read-only mode on top of the framework's default tool policy.
#
# Environment variables:
#   GIT_HEX_READ_ONLY=1  - Disable all mutating tools, allow only inspection tools
#
# This file is sourced into the server process, so it must not change shell
# options (no top-level `set -euo pipefail`).

# Tool policy hook - called before every tool execution.
# Defining this function replaces the framework's default check, which enforces
# MCPBASH_TOOL_ALLOWLIST, so run that check first.
mcp_tools_policy_check() {
	if declare -F mcp_tools_policy_check_default >/dev/null; then
		mcp_tools_policy_check_default "$@" || return 1
	fi

	local tool_name="$1"
	# shellcheck disable=SC2034
	local metadata="$2"

	# Read-only mode: only allow inspection tools
	if [ "${GIT_HEX_READ_ONLY:-}" = "1" ]; then
		case "${tool_name}" in
		git-hex-getRebasePlan | git-hex-checkRebaseConflicts | git-hex-getConflictStatus)
			# Inspection tool - allowed in read-only mode
			return 0
			;;
		git-hex-amendLastCommit | git-hex-createFixup | git-hex-cherryPickSingle | git-hex-rebaseWithPlan | git-hex-resolveConflict | git-hex-continueOperation | git-hex-abortOperation | git-hex-splitCommit | git-hex-undoLast)
			# Mutating tools - blocked in read-only mode
			mcp_tools_error -32602 "git-hex is running in read-only mode. Tool '${tool_name}' is disabled. Set GIT_HEX_READ_ONLY=0 to enable."
			return 1
			;;
		*)
			# Unknown tool - block by default in read-only mode (fail-safe)
			mcp_tools_error -32602 "git-hex is running in read-only mode. Tool '${tool_name}' is not recognized."
			return 1
			;;
		esac
	fi

	return 0
}
