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
force="$(mcp_args_bool '.force' --default false)"

# Validate git repository
git_hex_require_repo "${repo_path}"

# Check for any in-progress git operations
git_dir="$( git_hex_get_git_dir "${repo_path}")"
operation_in_progress="$(  git_hex_get_in_progress_operation_from_git_dir "${git_dir}")"
git_hex_require_no_in_progress_operation  "${operation_in_progress}"

# Check for uncommitted changes
if ! git -C "${repo_path}" diff --quiet -- 2>/dev/null || ! git -C "${repo_path}" diff --cached --quiet -- 2>/dev/null; then
	git_hex_error "UNCOMMITTED_CHANGES" "Repository has uncommitted changes." \
		"Commit or stash changes before undoing" \
		"Use 'git stash' to temporarily save changes"
fi

_git_hex_find_untracked_overwrites() {
	local repo="$1"
	local target_commit="$2"

	local -a untracked_files
	untracked_files=()
	while IFS= read -r -d '' f; do
		[ -n "${f}" ] || continue
		untracked_files+=("${f}")
	done < <(git -C "${repo}" ls-files -z --others --exclude-standard 2>/dev/null || true)

	[ "${#untracked_files[@]}" -gt 0 ] || return 0

	local -a overwrites
	overwrites=()
	while IFS= read -r -d '' tracked_path; do
		[ -n "${tracked_path}" ] || continue
		local u
		for u in "${untracked_files[@]}"; do
			if [ "${u}" = "${tracked_path}" ]; then
				overwrites+=("${u}")
				break
			fi
		done
	done < <(git -C "${repo}" ls-tree -r -z --name-only "${target_commit}^{tree}" 2>/dev/null || true)

	if [ "${#overwrites[@]}" -gt 0 ]; then
		printf '%s\n' "${overwrites[@]}"
	fi
	return 0
}

# Get the last backup info
backup_info="$(git_hex_get_last_backup "${repo_path}")"

if [ -z "${backup_info}" ]; then
	git_hex_error "NO_BACKUP" "No git-hex backup found." \
		"undoLast only works after a git-hex operation that created a backup" \
		"Use 'git reflog' to manually find and restore previous states"
fi

# Parse backup info (format: hash|operation|timestamp|ref)
IFS='|' read -r backup_hash operation timestamp backup_ref <<<"${backup_info}"

if [ -z "${backup_hash}" ]; then
	git_hex_error "NO_BACKUP" "No git-hex backup found." \
		"undoLast only works after a git-hex operation that created a backup" \
		"Use 'git reflog' to manually find and restore previous states"
fi

# Get current HEAD before undo
head_before="$(git -C "${repo_path}" rev-parse HEAD)"
recorded_head=""
ref_suffix=""
if [ -n "${backup_ref}" ]; then
	ref_suffix="${backup_ref#git-hex/backup/}"
fi
if  [ -z "${ref_suffix}" ] && [ -n "${timestamp}" ] && [ -n "${operation}" ]; then
	ref_suffix="${timestamp}_${operation}"
fi
if  [ -n "${ref_suffix}" ]; then
	recorded_head="$(git -C "${repo_path}" rev-parse --verify "refs/git-hex/last-head/${ref_suffix}^{commit}" 2>/dev/null || echo "")"
fi

# Check if we're already at the backup state
if [ "${head_before}" = "${backup_hash}" ]; then
	# Build and emit result (mcp_result_success wraps in {success: true, result: ...} envelope)
	# shellcheck disable=SC2016
	result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--arg headBefore "${head_before}" \
		--arg headAfter "${head_before}" \
		--arg undoneOperation "${operation:-unknown}" \
		--arg summary "Already at backup state - nothing to undo" \
		'{headBefore: $headBefore, headAfter: $headAfter, undoneOperation: $undoneOperation, summary: $summary}')"
	mcp_result_success "${result}"
	exit 0
fi

# Check if there are commits between backup and current HEAD that weren't made by git-hex
# This is a safety check to avoid losing work
commits_since_backup="$( git -C "${repo_path}" rev-list --count "${backup_hash}..HEAD" 2>/dev/null || echo "0")"
prev_head="$( git -C "${repo_path}" rev-parse --verify 'HEAD@{1}^{commit}' 2>/dev/null || echo "")"
# If we have a recorded head from the git-hex operation, use it to detect extra commits
if [ "${commits_since_backup}" -gt 0 ] && [ "${force}" = "false" ]; then
	if [ -n "${recorded_head}" ] && [ "${head_before}" != "${recorded_head}" ]; then
		git_hex_error "COMMITS_AFTER_BACKUP" "Refusing to undo: commits exist after the last git-hex operation." \
			"Use force=true to discard commits after the backup" \
			"Or save your work to a branch first with 'git branch backup-branch'"
	elif [ -z "${recorded_head}" ]; then
		# Fallback heuristic when recorded head is unavailable (older backups).
		# If reflogs are unavailable, we cannot safely determine whether there are extra commits.
		if [ -z "${prev_head}" ]; then
			git_hex_error "COMMITS_AFTER_BACKUP" "Refusing to undo: ${commits_since_backup} commit(s) after backup, reflogs are unavailable." \
				"Use force=true to discard commits after the backup" \
				"Or save your work to a branch first with 'git branch backup-branch'"
		fi
		if [ "${prev_head}" != "${backup_hash}" ]; then
			git_hex_error "COMMITS_AFTER_BACKUP" "Refusing to undo: ${commits_since_backup} commit(s) after the last git-hex operation." \
				"Use force=true to discard commits after the backup" \
				"Or save your work to a branch first with 'git branch backup-branch'"
		fi
	fi
fi

# Safety: refuse to overwrite untracked files by default.
# `git reset --hard` can overwrite an untracked file if the reset target has that path tracked.
if [ "${force}" = "false" ]; then
	untracked_overwrites="$(_git_hex_find_untracked_overwrites "${repo_path}" "${backup_hash}")"
	if [ -n "${untracked_overwrites}" ]; then
		# Keep the message compact; list up to 5 paths.
		count="$(printf '%s\n' "${untracked_overwrites}" | wc -l | tr -d ' ')"
		list="$(printf '%s\n' "${untracked_overwrites}" | head -n 5 | paste -sd ', ' -)"
		if [ "${count}" -gt 5 ]; then
			list="${list}, ..."
		fi
		git_hex_error "UNTRACKED_OVERWRITE" "Refusing to undo: ${count} untracked file(s) would be overwritten (${list})." \
			"Move or delete the conflicting files" \
			"Or use force=true to overwrite them"
	fi
fi

# Perform the reset
if ! git -C "${repo_path}" reset --hard "${backup_hash}" >/dev/null 2>&1; then
	git_hex_error "GIT_ERROR" "Failed to reset to backup state." \
		"The repository may be in an inconsistent state" \
		"Check 'git status' and 'git reflog' to diagnose"
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

# Build and emit result (mcp_result_success wraps in {success: true, result: ...} envelope)
# shellcheck disable=SC2016
result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--arg headBefore "${head_before}" \
	--arg headAfter "${head_after}" \
	--arg undoneOperation "${operation:-unknown}" \
	--arg backupRef "${backup_ref}" \
	--argjson commitsUndone "${commits_since_backup}" \
	--arg summary "${summary}" \
	'{headBefore: $headBefore, headAfter: $headAfter, undoneOperation: $undoneOperation, backupRef: $backupRef, commitsUndone: $commitsUndone, summary: $summary}')"
mcp_result_success "${result}"
