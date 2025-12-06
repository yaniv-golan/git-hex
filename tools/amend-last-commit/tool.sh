#!/usr/bin/env bash
set -euo pipefail

# Source SDK (MCP_SDK is set by the framework when running tools)
# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
new_message="$(mcp_args_get '.message // empty' || true)"
add_all="$(mcp_args_bool '.addAll' --default false)"

# Validate git repository
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

# Check if there are any commits
if ! git -C "${repo_path}" rev-parse HEAD >/dev/null 2>&1; then
	mcp_fail_invalid_args "Repository has no commits to amend"
fi

# Check if in rebase state
if [ -d "${repo_path}/.git/rebase-merge" ] || [ -d "${repo_path}/.git/rebase-apply" ]; then
	mcp_fail_invalid_args "Repository is in a rebase state. Please resolve or abort it first."
fi

# Save original HEAD
previous_hash="$(git -C "${repo_path}" rev-parse HEAD)"

# Stage all tracked files if requested
if [ "${add_all}" = "true" ]; then
	git -C "${repo_path}" add -u
fi

# Check if there's anything to amend (staged changes or new message)
staged_files="$(git -C "${repo_path}" diff --cached --name-only 2>/dev/null || true)"
if [ -z "${staged_files}" ] && [ -z "${new_message}" ]; then
	mcp_fail_invalid_args "Nothing to amend. Stage changes or provide a new message."
fi

# Build amend command
amend_args=("--amend")
if [ -n "${new_message}" ]; then
	amend_args+=("-m" "${new_message}")
else
	amend_args+=("--no-edit")
fi

# Perform the amend
if ! git -C "${repo_path}" commit "${amend_args[@]}" >&2; then
	mcp_fail -32603 "Failed to amend commit"
fi

# Get new commit info
new_hash="$(git -C "${repo_path}" rev-parse HEAD)"
final_message="$(git -C "${repo_path}" log -1 --format='%s' HEAD)"

mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg newHash "${new_hash}" \
	--arg previousHash "${previous_hash}" \
	--arg message "${final_message}" \
	'{success: $success, newHash: $newHash, previousHash: $previousHash, message: $message}')"
