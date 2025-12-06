#!/usr/bin/env bash
set -euo pipefail

# Source SDK (MCP_SDK is set by the framework when running tools)
# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

# Source backup helper for undo support
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/backup.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/backup.sh"

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

# Check for any in-progress git operations
if [ -d "${repo_path}/.git/rebase-merge" ] || [ -d "${repo_path}/.git/rebase-apply" ]; then
	mcp_fail_invalid_args "Repository is in a rebase state. Please resolve or abort it first."
fi
if [ -f "${repo_path}/.git/CHERRY_PICK_HEAD" ]; then
	mcp_fail_invalid_args "Repository is in a cherry-pick state. Please resolve or abort it first."
fi
if [ -f "${repo_path}/.git/MERGE_HEAD" ]; then
	mcp_fail_invalid_args "Repository is in a merge state. Please resolve or abort it first."
fi

# Save original HEAD for headBefore/headAfter consistency
head_before="$(git -C "${repo_path}" rev-parse HEAD)"

# Create backup ref for undo support (before any mutations)
git_hex_create_backup "${repo_path}" "amendLastCommit" >/dev/null

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

# Perform the amend (capture stderr for better error messages)
commit_error=""
if ! commit_error="$(git -C "${repo_path}" commit "${amend_args[@]}" 2>&1)"; then
	# Provide specific error context
	if echo "${commit_error}" | grep -qi "gpg\|signing\|sign"; then
		mcp_fail -32603 "Failed to amend commit: GPG signing error. Check your signing configuration or use 'git config commit.gpgsign false' to disable."
	elif echo "${commit_error}" | grep -qi "hook"; then
		mcp_fail -32603 "Failed to amend commit: A git hook rejected the commit. Check your pre-commit or commit-msg hooks."
	else
		# Include first line of error for context
		error_hint="$(echo "${commit_error}" | head -1)"
		mcp_fail -32603 "Failed to amend commit: ${error_hint}"
	fi
fi
# Echo output to stderr for logging
printf '%s\n' "${commit_error}" >&2

# Get new commit info
head_after="$(git -C "${repo_path}" rev-parse HEAD)"
commit_message="$(git -C "${repo_path}" log -1 --format='%s' HEAD)"

mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg headBefore "${head_before}" \
	--arg headAfter "${head_after}" \
	--arg summary "Amended commit with new hash ${head_after:0:7}" \
	--arg commitMessage "${commit_message}" \
	'{success: $success, headBefore: $headBefore, headAfter: $headAfter, summary: $summary, commitMessage: $commitMessage}')"
