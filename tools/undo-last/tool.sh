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

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
force="$(mcp_args_bool '.force' --default false)"

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

# Check for uncommitted changes
if ! git -C "${repo_path}" diff-index --quiet HEAD -- 2>/dev/null; then
	mcp_fail_invalid_args "Repository has uncommitted changes. Please commit or stash them first."
fi

# Get the last backup info
backup_info="$(git_hex_get_last_backup "${repo_path}")"

if [ -z "${backup_info}" ]; then
	mcp_fail_invalid_args "No git-hex backup found. Nothing to undo."
fi

# Parse backup info (format: hash|operation|timestamp|ref)
IFS='|' read -r backup_hash operation timestamp backup_ref <<<"${backup_info}"

if [ -z "${backup_hash}" ]; then
	mcp_fail_invalid_args "No git-hex backup found. Nothing to undo."
fi

# Get current HEAD before undo
head_before="$(git -C "${repo_path}" rev-parse HEAD)"
recorded_head=""
ref_suffix=""
if [ -n "${backup_ref}" ]; then
	ref_suffix="${backup_ref#git-hex/backup/}"
fi
if [ -z "${ref_suffix}" ] && [ -n "${timestamp}" ] && [ -n "${operation}" ]; then
	ref_suffix="${timestamp}_${operation}"
fi
if [ -n "${ref_suffix}" ]; then
	recorded_head="$(git -C "${repo_path}" rev-parse "refs/git-hex/last-head/${ref_suffix}" 2>/dev/null || echo "")"
fi

# Check if we're already at the backup state
if [ "${head_before}" = "${backup_hash}" ]; then
	# shellcheck disable=SC2016
	mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--argjson success true \
		--arg headBefore "${head_before}" \
		--arg headAfter "${head_before}" \
		--arg undoneOperation "${operation:-unknown}" \
		--arg summary "Already at backup state - nothing to undo" \
		'{success: $success, headBefore: $headBefore, headAfter: $headAfter, undoneOperation: $undoneOperation, summary: $summary}')"
	exit 0
fi

# Check if there are commits between backup and current HEAD that weren't made by git-hex
# This is a safety check to avoid losing work
commits_since_backup="$(git -C "${repo_path}" rev-list --count "${backup_hash}..HEAD" 2>/dev/null || echo "0")"
prev_head="$(git -C "${repo_path}" rev-parse 'HEAD@{1}' 2>/dev/null || echo "")"
# If we have a recorded head from the git-hex operation, use it to detect extra commits
if [ "${commits_since_backup}" -gt 0 ] && [ "${force}" = "false" ]; then
	if [ -n "${recorded_head}" ] && [ "${head_before}" != "${recorded_head}" ]; then
		mcp_fail_invalid_args "Refusing to undo because there are commits after the last git-hex operation. Re-run with force=true to discard them."
	elif [ -z "${recorded_head}" ] && [ -n "${prev_head}" ] && [ "${prev_head}" != "${backup_hash}" ]; then
		# Fallback heuristic when recorded head is unavailable (older backups)
		mcp_fail_invalid_args "Refusing to undo because there are ${commits_since_backup} commit(s) after the last git-hex operation. Re-run with force=true to discard them."
	fi
fi

# Perform the reset
if ! git -C "${repo_path}" reset --hard "${backup_hash}" >/dev/null 2>&1; then
	mcp_fail -32603 "Failed to reset to backup state"
fi

# Get new HEAD after undo
head_after="$(git -C "${repo_path}" rev-parse HEAD)"

# Format timestamp for display
formatted_time=""
if [ -n "${timestamp}" ]; then
	# Convert Unix timestamp to human-readable format
	if command -v date >/dev/null 2>&1; then
		formatted_time="$(date -r "${timestamp}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@${timestamp}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")"
	fi
fi

# Build summary message
summary="Undid ${operation:-unknown operation}"
if [ -n "${formatted_time}" ]; then
	summary="${summary} from ${formatted_time}"
fi
summary="${summary}. Reset ${commits_since_backup} commit(s) from ${head_before:0:7} to ${head_after:0:7}"
if [ "${force}" = "true" ] && [ "${commits_since_backup}" -gt 0 ]; then
	summary="${summary} (forced)"
fi

# shellcheck disable=SC2016
mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg headBefore "${head_before}" \
	--arg headAfter "${head_after}" \
	--arg undoneOperation "${operation:-unknown}" \
	--arg backupRef "${backup_ref}" \
	--argjson commitsUndone "${commits_since_backup}" \
	--arg summary "${summary}" \
	'{success: $success, headBefore: $headBefore, headAfter: $headAfter, undoneOperation: $undoneOperation, backupRef: $backupRef, commitsUndone: $commitsUndone, summary: $summary}')"
