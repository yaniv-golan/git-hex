#!/usr/bin/env bash
set -euo pipefail

# Enable shell tracing for debugging (shows every command executed)
if [ "${GIT_HEX_DEBUG:-}" = "true" ]; then
	set -x
fi

# Source SDK (MCP_SDK is set by the framework when running tools)
# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

# Source backup helper for undo support
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/backup.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/backup.sh"
# shellcheck source=../../lib/git-helpers.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/git-helpers.sh"
# shellcheck source=../../lib/stash.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/stash.sh"

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
new_message="$(mcp_args_get '.message // empty' || true)"
add_all="$(mcp_args_bool '.addAll' --default false)"
auto_stash="$(mcp_args_bool '.autoStash' --default false)"
sign_commits="$(mcp_args_bool '.signCommits' --default false)"

# Validate git repository
git_hex_require_repo "${repo_path}"

# Check if there are any commits
if ! git -C "${repo_path}" rev-parse HEAD >/dev/null 2>&1; then
	mcp_fail_invalid_args "Repository has no commits to amend"
fi

# Check for any in-progress git operations
git_dir="$( git_hex_get_git_dir "${repo_path}")"
operation="$(  git_hex_get_in_progress_operation_from_git_dir "${git_dir}")"
git_hex_require_no_in_progress_operation  "${operation}"

# Handle auto-stash (unstaged changes only; keep index)
stash_created="false"
stash_not_restored="false"
if [ "${auto_stash}" = "true" ]; then
	stash_created="$(git_hex_auto_stash "${repo_path}" "keep-index")"
fi

# Save original HEAD for headBefore/headAfter consistency
head_before="$(git -C "${repo_path}" rev-parse HEAD)"

# Stage all tracked files if requested
if [ "${add_all}" = "true" ]; then
	git -C "${repo_path}" add -u
fi

# Check if there's anything to amend (staged changes or new message)
staged_files="$(git -C "${repo_path}" diff --cached --name-only 2>/dev/null || true)"
if [ -z "${staged_files}" ] && [ -z "${new_message}" ]; then
	mcp_fail_invalid_args "Nothing to amend. Stage changes or provide a new message."
fi

# Create backup ref for undo support (after validation, before mutations)
backup_ref="$( git_hex_create_backup "${repo_path}" "amendLastCommit")"

# Build amend command
amend_args=("--amend")
if [ -n "${new_message}" ]; then
	amend_args+=("-m" "${new_message}")
else
	amend_args+=("--no-edit")
fi
if [ "${sign_commits}" != "true" ]; then
	amend_args+=("--no-gpg-sign")
fi

# Perform the amend (capture stderr for better error messages)
commit_error=""
if ! commit_error="$(git -C "${repo_path}" commit "${amend_args[@]}" 2>&1)"; then
	# On failure, attempt to restore stash if we created one
	if [ "${auto_stash}" = "true" ]; then
		stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
	fi
	# Provide specific error context
	if grep -qi "gpg\\|signing\\|sign" <<<"${commit_error}"; then
		mcp_fail -32603 "Failed to amend commit: GPG signing error. Check your signing configuration or use 'git config commit.gpgsign false' to disable."
	elif grep -qi "hook\\|pre-commit\\|commit-msg" <<<"${commit_error}"; then
		mcp_fail -32603 "Failed to amend commit: A git hook rejected the commit. Check your pre-commit or commit-msg hooks."
	else
		# Include first line of error for context
		error_hint="${commit_error%%$'\n'*}"
		mcp_fail -32603 "Failed to amend commit: ${error_hint}"
	fi
fi
# Echo output to stderr for logging
printf '%s\n' "${commit_error}" >&2

# Restore stash after successful amend
if [ "${auto_stash}" = "true" ]; then
	stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
fi

# Get new commit info
head_after="$(git -C "${repo_path}" rev-parse HEAD)"
commit_message="$(git -C "${repo_path}" log -1 --format='%s' HEAD)"

# Record post-operation state for undo safety checks
git_hex_record_last_head "${repo_path}" "${head_after}"

# shellcheck disable=SC2016
mcp_emit_json  "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg headBefore "${head_before}" \
	--arg headAfter "${head_after}" \
	--arg backupRef "${backup_ref}" \
	--arg summary "Amended commit with new hash ${head_after:0:7}" \
	--arg commitMessage "${commit_message}" \
	--argjson stashNotRestored "${stash_not_restored}" \
	'{success: $success, headBefore: $headBefore, headAfter: $headAfter, backupRef: $backupRef, summary: $summary, commitMessage: $commitMessage, stashNotRestored: $stashNotRestored}')"
