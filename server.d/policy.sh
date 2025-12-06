#!/usr/bin/env bash
# Tool execution policy for git-hex
#
# Overrides the framework's default mcp_tools_policy_check to implement
# read-only mode and other access controls.
#
# Environment variables:
#   GIT_HEX_READ_ONLY=1  - Disable all mutating tools, allow only inspection tools

set -euo pipefail

# Tool policy hook - called before every tool execution
# See: mcp-bash-framework lib/tools_policy.sh for default implementation
mcp_tools_policy_check() {
	local tool_name="$1"
	# shellcheck disable=SC2034
	local metadata="$2"

	# Read-only mode: only allow inspection tools
	if [ "${GIT_HEX_READ_ONLY:-}" = "1" ]; then
		case "${tool_name}" in
		gitHex.getRebasePlan | gitHex.checkRebaseConflicts | gitHex.getConflictStatus)
			# Inspection tool - allowed in read-only mode
			return 0
			;;
		gitHex.amendLastCommit | gitHex.createFixup | gitHex.cherryPickSingle | gitHex.rebaseWithPlan | gitHex.resolveConflict | gitHex.continueOperation | gitHex.abortOperation | gitHex.splitCommit | gitHex.undoLast)
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

	# Default: allow all tools
	return 0
}
