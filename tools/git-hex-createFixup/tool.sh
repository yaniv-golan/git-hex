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

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
commit="$(mcp_args_require '.commit')"
extra_message="$(mcp_args_get '.message // empty' || true)"
sign_commits="$(mcp_args_bool '.signCommits' --default false)"

# Validate git repository
git_hex_require_repo "${repo_path}"

# Check for any in-progress git operations
git_dir="$(git_hex_get_git_dir "${repo_path}")"
operation="$(git_hex_get_in_progress_operation_from_git_dir "${git_dir}")"
case "${operation}" in
rebase) mcp_fail_invalid_args "Repository is in a rebase state. Please resolve or abort it first." ;;
cherry-pick) mcp_fail_invalid_args "Repository is in a cherry-pick state. Please resolve or abort it first." ;;
merge) mcp_fail_invalid_args "Repository is in a merge state. Please resolve or abort it first." ;;
esac

# Verify target commit exists and resolve to full hash
target_hash="$(git -C "${repo_path}" rev-parse "${commit}" 2>/dev/null || true)"
if [ -z "${target_hash}" ]; then
	mcp_fail_invalid_args "Invalid commit ref: ${commit}"
fi

# Save HEAD before operation for headBefore/headAfter consistency
head_before="$(git -C "${repo_path}" rev-parse HEAD)"

# Check for staged changes
staged_files="$(git -C "${repo_path}" diff --cached --name-only 2>/dev/null || true)"
if [ -z "${staged_files}" ]; then
	mcp_fail_invalid_args "No staged changes. Stage changes with 'git add' before creating a fixup commit."
fi

# Create backup ref for undo support (after validation, before mutations)
git_hex_create_backup "${repo_path}" "createFixup" >/dev/null

# Get the original commit's subject for the fixup message
original_subject="$(git -C "${repo_path}" log -1 --format='%s' "${target_hash}" 2>/dev/null || true)"

# Helper to handle commit errors with better messages
handle_commit_error()  {
	local commit_error="$1"
	if grep -qi "gpg\\|signing\\|sign" <<<"${commit_error}"; then
		mcp_fail -32603 "Failed to create fixup commit: GPG signing error. Check your signing configuration or use 'git config commit.gpgsign false' to disable."
	elif grep -qi "hook" <<<"${commit_error}"; then
		mcp_fail -32603 "Failed to create fixup commit: A git hook rejected the commit. Check your pre-commit or commit-msg hooks."
	else
		error_hint="$(echo "${commit_error}" | head -1)"
		mcp_fail -32603 "Failed to create fixup commit: ${error_hint}"
	fi
}

# Create the fixup commit (capture stderr for better error messages)
commit_error=""
if [ -n "${extra_message}" ]; then
	# Use commit with custom message that includes fixup! prefix
	full_message="fixup! ${original_subject}

${extra_message}"
	commit_args=("-m" "${full_message}")
	if [ "${sign_commits}" != "true" ]; then
		commit_args+=("--no-gpg-sign")
	fi
	if ! commit_error="$(git -C "${repo_path}" commit "${commit_args[@]}" 2>&1)"; then
		handle_commit_error "${commit_error}"
	fi
else
	# Use git's built-in fixup
	commit_args=("--fixup=${target_hash}")
	if [ "${sign_commits}" != "true" ]; then
		commit_args+=("--no-gpg-sign")
	fi
	if ! commit_error="$(git -C "${repo_path}" commit "${commit_args[@]}" 2>&1)"; then
		handle_commit_error "${commit_error}"
	fi
fi
# Echo output to stderr for logging
printf '%s\n' "${commit_error}" >&2

# Get the new commit hash and message
head_after="$(git -C "${repo_path}" rev-parse HEAD)"
commit_message="$(git -C "${repo_path}" log -1 --format='%s' HEAD)"

# Record post-operation state for undo safety checks
git_hex_record_last_head "${repo_path}" "${head_after}"

# shellcheck disable=SC2016
mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg headBefore "${head_before}" \
	--arg headAfter "${head_after}" \
	--arg targetCommit "${target_hash}" \
	--arg summary "Created fixup commit ${head_after:0:7} targeting ${target_hash:0:7}" \
	--arg commitMessage "${commit_message}" \
	'{success: $success, headBefore: $headBefore, headAfter: $headAfter, targetCommit: $targetCommit, summary: $summary, commitMessage: $commitMessage}')"
