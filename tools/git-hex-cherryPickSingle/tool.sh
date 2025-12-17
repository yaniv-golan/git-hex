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
# shellcheck source=../../lib/stash.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/stash.sh"

# Cleanup function to abort cherry-pick on failure
cleanup() {
	if [ -n "${repo_path:-}" ]; then
		git_dir="$(git -C "${repo_path}" rev-parse --git-dir 2>/dev/null || true)"
		if [ -n "${git_dir}" ]; then
			case "${git_dir}" in
			/*) ;;
			*) git_dir="${repo_path}/${git_dir}" ;;
			esac
			cherry_pick_head_path="${git_dir}/CHERRY_PICK_HEAD"
		else
			cherry_pick_head_path=""
		fi
		if [ "${_git_hex_cleanup_abort:-true}" = "true" ] && [ -n "${cherry_pick_head_path}" ] && [ -f "${cherry_pick_head_path}" ]; then
			git -C "${repo_path}" cherry-pick --abort >/dev/null 2>&1 || true
		fi
	fi
	return 0
}
trap cleanup EXIT

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
commit="$(mcp_args_require '.commit')"
strategy="$(mcp_args_get '.strategy // empty' || true)"
no_commit="$(mcp_args_bool '.noCommit' --default false)"
abort_on_conflict="$(mcp_args_bool '.abortOnConflict' --default true)"
auto_stash="$(mcp_args_bool '.autoStash' --default false)"
sign_commits="$(mcp_args_bool '.signCommits' --default false)"
_git_hex_cleanup_abort="true"

# Validate autoStash vs abortOnConflict
if [ "${auto_stash}" = "true" ] && [ "${abort_on_conflict}" = "false" ]; then
	mcp_fail_invalid_args "autoStash cannot be used with abortOnConflict=false for cherry-pick. Use git stash manually."
fi

# Validate strategy if provided (must match schema enum)
# Note: octopus is excluded - it's for multi-branch merges, not cherry-pick
if [ -n "${strategy}" ]; then
	case "${strategy}" in
	recursive | resolve)
		# Valid strategy (available in all git versions)
		;;
	ort)
		# ort strategy requires git 2.33+
		git_version="$(git --version | sed 's/git version //' | cut -d. -f1-2)"
		# Compare major.minor >= 2.33
		major="${git_version%%.*}"
		minor="${git_version#*.}"
		if [ "${major}" -lt 2 ] || { [ "${major}" -eq 2 ] && [ "${minor}" -lt 33 ]; }; then
			mcp_fail_invalid_args "Merge strategy 'ort' requires git 2.33+. Current version: ${git_version}. Use 'recursive' instead."
		fi
		;;
	*)
		mcp_fail_invalid_args "Invalid merge strategy '${strategy}'. Must be one of: recursive, ort, resolve"
		;;
	esac
fi

# Validate git repository
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

# Check if repository has any commits
if ! git -C "${repo_path}" rev-parse HEAD >/dev/null 2>&1; then
	mcp_fail_invalid_args "Repository has no commits. Nothing to cherry-pick onto."
fi

# Check for any in-progress git operations
git_dir="$(git -C "${repo_path}" rev-parse --git-dir 2>/dev/null || true)"
case "${git_dir}" in
/*) ;;
*) git_dir="${repo_path}/${git_dir}" ;;
esac
rebase_merge_dir="${git_dir}/rebase-merge"
rebase_apply_dir="${git_dir}/rebase-apply"
cherry_pick_head_path="${git_dir}/CHERRY_PICK_HEAD"
merge_head_path="${git_dir}/MERGE_HEAD"
if { [ -n "${rebase_merge_dir}" ] && [ -d "${rebase_merge_dir}" ]; } || { [ -n "${rebase_apply_dir}" ] && [ -d "${rebase_apply_dir}" ]; }; then
	mcp_fail_invalid_args "Repository is in a rebase state. Please resolve or abort it first."
fi
if [ -n "${cherry_pick_head_path}" ] && [ -f "${cherry_pick_head_path}" ]; then
	mcp_fail_invalid_args "Repository is in a cherry-pick state. Please resolve or abort it first."
fi
if [ -n "${merge_head_path}" ] && [ -f "${merge_head_path}" ]; then
	mcp_fail_invalid_args "Repository is in a merge state. Please resolve or abort it first."
fi

# Save HEAD before operation for headBefore/headAfter consistency
head_before="$(git -C "${repo_path}" rev-parse HEAD)"

# Create backup ref for undo support (before any mutations)
git_hex_create_backup "${repo_path}" "cherryPickSingle" >/dev/null

# Handle manual auto-stash
stash_created="false"
stash_not_restored="false"
if [ "${auto_stash}" = "true" ]; then
	stash_created="$(git_hex_auto_stash "${repo_path}")"
else
	if ! git -C "${repo_path}" diff --quiet -- 2>/dev/null || ! git -C "${repo_path}" diff --cached --quiet -- 2>/dev/null; then
		mcp_fail_invalid_args "Repository has uncommitted changes. Please commit or stash them first."
	fi
fi

# Verify commit exists and resolve to full hash
source_hash="$(git -C "${repo_path}" rev-parse "${commit}" 2>/dev/null || true)"
if [ -z "${source_hash}" ]; then
	mcp_fail_invalid_args "Invalid commit ref: ${commit}"
fi

# Get source commit's subject for commitMessage
source_subject="$(git -C "${repo_path}" log -1 --format='%s' "${source_hash}" 2>/dev/null || true)"

# Build cherry-pick command
pick_args=()
if [ -n "${strategy}" ]; then
	pick_args+=("--strategy=${strategy}")
fi
if [ "${no_commit}" = "true" ]; then
	pick_args+=("--no-commit")
fi
if [ "${sign_commits}" != "true" ] && [ "${no_commit}" != "true" ]; then
	pick_args+=("--no-gpg-sign")
fi
pick_args+=("${source_hash}")

# Perform cherry-pick (capture stderr for better error messages)
pick_error=""
if pick_error="$(git -C "${repo_path}" cherry-pick "${pick_args[@]}" 2>&1)"; then
	# Success - clear the trap
	trap - EXIT
	# Echo output to stderr for logging
	printf '%s\n' "${pick_error}" >&2

	head_after="$(git -C "${repo_path}" rev-parse HEAD)"

	# Restore stash if created
	if [ "${auto_stash}" = "true" ]; then
		stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
	fi

	# Record post-operation state for undo safety checks
	git_hex_record_last_head "${repo_path}" "${head_after}"

	if [ "${no_commit}" = "true" ]; then
		# shellcheck disable=SC2016
		mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--argjson success true \
			--arg headBefore "${head_before}" \
			--arg headAfter "${head_after}" \
			--arg sourceCommit "${source_hash}" \
			--arg summary "Changes from ${source_hash:0:7} applied but not committed (staged)" \
			--arg commitMessage "${source_subject}" \
			--argjson stashNotRestored "${stash_not_restored}" \
			'{success: $success, headBefore: $headBefore, headAfter: $headAfter, sourceCommit: $sourceCommit, summary: $summary, commitMessage: $commitMessage, stashNotRestored: $stashNotRestored}')"
	else
		# shellcheck disable=SC2016
		mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--argjson success true \
			--arg headBefore "${head_before}" \
			--arg headAfter "${head_after}" \
			--arg sourceCommit "${source_hash}" \
			--arg summary "Cherry-picked ${source_hash:0:7} as new commit ${head_after:0:7}" \
			--arg commitMessage "${source_subject}" \
			--argjson stashNotRestored "${stash_not_restored}" \
			'{success: $success, headBefore: $headBefore, headAfter: $headAfter, sourceCommit: $sourceCommit, summary: $summary, commitMessage: $commitMessage, stashNotRestored: $stashNotRestored}')"
	fi
else
	# Cherry-pick failed - cleanup will abort
	# Provide more specific error context
	if echo "${pick_error}" | grep -qi "conflict"; then
		if [ "${abort_on_conflict}" = "false" ]; then
			_git_hex_cleanup_abort="false"
			trap - EXIT
			head_after_pause="$(git -C "${repo_path}" rev-parse HEAD 2>/dev/null || echo "")"
			conflicting_files="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"
			conflicting_json="[]"
			while IFS= read -r cf; do
				[ -z "${cf}" ] && continue
				# shellcheck disable=SC2016
				conflicting_json="$(printf '%s' "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
			done <<<"${conflicting_files}"
			# shellcheck disable=SC2016
			mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
				--argjson success false \
				--argjson paused true \
				--arg reason "conflict" \
				--arg headBefore "${head_before}" \
				--arg headAfter "${head_after_pause}" \
				--arg sourceCommit "${source_hash}" \
				--argjson conflictingFiles "${conflicting_json}" \
				--arg summary "Cherry-pick paused due to conflicts. Use getConflictStatus and resolveConflict to continue." \
				'{success: $success, paused: $paused, reason: $reason, headBefore: $headBefore, headAfter: $headAfter, sourceCommit: $sourceCommit, conflictingFiles: $conflictingFiles, summary: $summary}')"
		else
			git_dir="$(git -C "${repo_path}" rev-parse --git-dir 2>/dev/null || true)"
			case "${git_dir}" in
			/*) ;;
			*) git_dir="${repo_path}/${git_dir}" ;;
			esac
			cherry_pick_head_path="${git_dir}/CHERRY_PICK_HEAD"
			if [ -n "${cherry_pick_head_path}" ] && [ -f "${cherry_pick_head_path}" ]; then
				git -C "${repo_path}" cherry-pick --abort >/dev/null 2>&1 || true
			fi
			if [ "${auto_stash}" = "true" ]; then
				stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
			fi
			mcp_fail -32603 "Cherry-pick failed due to conflicts. Repository has been restored to original state."
		fi
	elif echo "${pick_error}" | grep -qi "gpg\|signing\|sign"; then
		[ "${auto_stash}" = "true" ] && stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
		mcp_fail -32603 "Cherry-pick failed: GPG signing error. Check your signing configuration or use 'git config commit.gpgsign false' to disable."
	elif echo "${pick_error}" | grep -qi "empty"; then
		[ "${auto_stash}" = "true" ] && stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
		mcp_fail -32603 "Cherry-pick failed: The commit would be empty (changes already exist in HEAD)."
	else
		[ "${auto_stash}" = "true" ] && stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
		error_hint="$(echo "${pick_error}" | head -1)"
		mcp_fail -32603 "Cherry-pick failed: ${error_hint}. Repository has been restored to original state."
	fi
fi
