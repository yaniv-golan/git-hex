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

# Get the original commit's subject for the fixup message
original_subject="$(git -C "${repo_path}" log -1 --format='%s' "${target_hash}" 2>/dev/null || true)"

# Helper to handle commit errors with better messages
handle_commit_error() {
	local commit_error="$1"
	if echo "${commit_error}" | grep -qi "gpg\|signing\|sign"; then
		mcp_fail -32603 "Failed to create fixup commit: GPG signing error. Check your signing configuration or use 'git config commit.gpgsign false' to disable."
	elif echo "${commit_error}" | grep -qi "hook"; then
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
	if ! commit_error="$(git -C "${repo_path}" commit -m "${full_message}" 2>&1)"; then
		handle_commit_error "${commit_error}"
	fi
else
	# Use git's built-in fixup
	if ! commit_error="$(git -C "${repo_path}" commit --fixup="${target_hash}" 2>&1)"; then
		handle_commit_error "${commit_error}"
	fi
fi
# Echo output to stderr for logging
printf '%s\n' "${commit_error}" >&2

# Get the new commit hash and message
head_after="$(git -C "${repo_path}" rev-parse HEAD)"
commit_message="$(git -C "${repo_path}" log -1 --format='%s' HEAD)"

mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg headBefore "${head_before}" \
	--arg headAfter "${head_after}" \
	--arg targetCommit "${target_hash}" \
	--arg summary "Created fixup commit ${head_after:0:7} targeting ${target_hash:0:7}" \
	--arg commitMessage "${commit_message}" \
	'{success: $success, headBefore: $headBefore, headAfter: $headAfter, targetCommit: $targetCommit, summary: $summary, commitMessage: $commitMessage}')"
