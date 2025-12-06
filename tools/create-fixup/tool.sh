#!/usr/bin/env bash
set -euo pipefail

# Source SDK (MCP_SDK is set by the framework when running tools)
# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
commit="$(mcp_args_require '.commit')"
extra_message="$(mcp_args_get '.message // empty' || true)"

# Validate git repository
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

# Verify target commit exists and resolve to full hash
target_hash="$(git -C "${repo_path}" rev-parse "${commit}" 2>/dev/null || true)"
if [ -z "${target_hash}" ]; then
	mcp_fail_invalid_args "Invalid commit ref: ${commit}"
fi

# Check for staged changes
staged_files="$(git -C "${repo_path}" diff --cached --name-only 2>/dev/null || true)"
if [ -z "${staged_files}" ]; then
	mcp_fail_invalid_args "No staged changes. Stage changes with 'git add' before creating a fixup commit."
fi

# Get the original commit's subject for the fixup message
original_subject="$(git -C "${repo_path}" log -1 --format='%s' "${target_hash}" 2>/dev/null || true)"

# Create the fixup commit
if [ -n "${extra_message}" ]; then
	# Use commit with custom message that includes fixup! prefix
	full_message="fixup! ${original_subject}

${extra_message}"
	if ! git -C "${repo_path}" commit -m "${full_message}" >&2; then
		mcp_fail -32603 "Failed to create fixup commit"
	fi
else
	# Use git's built-in fixup
	if ! git -C "${repo_path}" commit --fixup="${target_hash}" >&2; then
		mcp_fail -32603 "Failed to create fixup commit"
	fi
fi

# Get the new commit hash and message
fixup_hash="$(git -C "${repo_path}" rev-parse HEAD)"
fixup_message="$(git -C "${repo_path}" log -1 --format='%s' HEAD)"

mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg fixupHash "${fixup_hash}" \
	--arg targetCommit "${target_hash}" \
	--arg message "${fixup_message}" \
	'{success: $success, fixupHash: $fixupHash, targetCommit: $targetCommit, message: $message}')"
