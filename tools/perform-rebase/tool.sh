#!/usr/bin/env bash
set -euo pipefail

# Source SDK (MCP_SDK is set by the framework when running tools)
# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

# Cleanup function to ensure we don't leave repo in bad state
cleanup() {
	if [ -n "${repo_path:-}" ]; then
		if [ -d "${repo_path}/.git/rebase-merge" ] || [ -d "${repo_path}/.git/rebase-apply" ]; then
			git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
		fi
	fi
}
trap cleanup EXIT

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
onto="$(mcp_args_require '.onto')"
autosquash="$(mcp_args_bool '.autosquash' --default true)"

# Validate git repository
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

# Check if repository has any commits
if ! git -C "${repo_path}" rev-parse HEAD >/dev/null 2>&1; then
	mcp_fail_invalid_args "Repository has no commits. Nothing to rebase."
fi

# Check for uncommitted changes
if ! git -C "${repo_path}" diff-index --quiet HEAD -- 2>/dev/null; then
	mcp_fail_invalid_args "Repository has uncommitted changes. Please commit or stash them first."
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

# Verify onto ref exists
if ! git -C "${repo_path}" rev-parse "${onto}" >/dev/null 2>&1; then
	mcp_fail_invalid_args "Invalid onto ref: ${onto}"
fi

# Save HEAD before operation for headBefore/headAfter consistency
head_before="$(git -C "${repo_path}" rev-parse HEAD)"

# Count commits to be rebased
commit_count="$(git -C "${repo_path}" rev-list --count "${onto}..HEAD" 2>/dev/null || echo "0")"

if [ "${commit_count}" = "0" ]; then
	mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--argjson success true \
		--arg headBefore "${head_before}" \
		--arg headAfter "${head_before}" \
		--arg summary "Nothing to rebase - HEAD is already at or behind ${onto}" \
		--argjson commitsRebased 0 \
		'{success: $success, headBefore: $headBefore, headAfter: $headAfter, summary: $summary, commitsRebased: $commitsRebased}')"
	exit 0
fi

mcp_progress 10 "Starting rebase of ${commit_count} commits onto ${onto}"

# Build rebase command
rebase_args=("--onto" "${onto}" "${onto}")
if [ "${autosquash}" = "true" ]; then
	rebase_args=("--autosquash" "${rebase_args[@]}")
fi

# Perform rebase (non-interactive to avoid editor)
# Use GIT_SEQUENCE_EDITOR=true to auto-accept the todo list
# Capture stderr for better error messages
rebase_error=""
if rebase_error="$(GIT_SEQUENCE_EDITOR=true git -C "${repo_path}" rebase -i "${rebase_args[@]}" 2>&1)"; then
	# Success - clear the trap since we don't need cleanup
	trap - EXIT
	# Echo output to stderr for logging
	printf '%s\n' "${rebase_error}" >&2
	
	head_after="$(git -C "${repo_path}" rev-parse HEAD)"
	
	mcp_progress 100 "Rebase completed successfully"
	mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--argjson success true \
		--arg headBefore "${head_before}" \
		--arg headAfter "${head_after}" \
		--arg summary "Rebased ${commit_count} commits onto ${onto}" \
		--argjson commitsRebased "${commit_count}" \
		'{success: $success, headBefore: $headBefore, headAfter: $headAfter, summary: $summary, commitsRebased: $commitsRebased}')"
else
	# Rebase failed - cleanup will abort
	# Provide more specific error context
	if echo "${rebase_error}" | grep -qi "conflict"; then
		mcp_fail -32603 "Rebase failed due to conflicts. Repository has been restored to original state."
	elif echo "${rebase_error}" | grep -qi "gpg\|signing\|sign"; then
		mcp_fail -32603 "Rebase failed: GPG signing error. Check your signing configuration or use 'git config commit.gpgsign false' to disable."
	elif echo "${rebase_error}" | grep -qi "hook"; then
		mcp_fail -32603 "Rebase failed: A git hook rejected a commit. Check your pre-commit or commit-msg hooks."
	elif echo "${rebase_error}" | grep -qi "exec"; then
		mcp_fail -32603 "Rebase failed: An exec command in the rebase todo failed."
	else
		error_hint="$(echo "${rebase_error}" | head -1)"
		mcp_fail -32603 "Rebase failed: ${error_hint}. Repository has been restored to original state."
	fi
fi
