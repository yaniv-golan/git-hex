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

# Restrict-only hook (mcp-bash 1.8+). The framework runs it after its own
# checks (the MCPBASH_TOOL_ALLOWLIST allowlist and tool path checks), so it can
# only narrow them. Exit 0 allows the call; any other status denies it, and what
# the hook prints becomes the denial message the model and the user see.
mcp_tools_policy_project() {
	local tool_name="$1"

	# Read-only mode: only allow inspection tools
	if [ "${GIT_HEX_READ_ONLY:-}" = "1" ]; then
		case "${tool_name}" in
		git-hex-getRebasePlan | git-hex-checkRebaseConflicts | git-hex-getConflictStatus)
			# Inspection tool - allowed in read-only mode
			return 0
			;;
		git-hex-amendLastCommit | git-hex-createFixup | git-hex-cherryPickSingle | git-hex-rebaseWithPlan | git-hex-resolveConflict | git-hex-continueOperation | git-hex-abortOperation | git-hex-splitCommit | git-hex-undoLast)
			# Mutating tools - blocked in read-only mode
			printf '%s' "git-hex is running in read-only mode. Tool '${tool_name}' is disabled. Set GIT_HEX_READ_ONLY=0 to enable."
			return 1
			;;
		*)
			# Unknown tool - block by default in read-only mode (fail-safe)
			printf '%s' "git-hex is running in read-only mode. Tool '${tool_name}' is not recognized."
			return 1
			;;
		esac
	fi

	return 0
}
