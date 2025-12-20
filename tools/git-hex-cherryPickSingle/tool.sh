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

# Cleanup function to abort cherry-pick on failure
cleanup() {
	if [ -n "${repo_path:-}" ]; then
		git_dir="$(git_hex_get_git_dir "${repo_path}" 2>/dev/null || true)"
		cherry_pick_head_path=""
		if [ -n "${git_dir}" ]; then
			cherry_pick_head_path="${git_dir}/CHERRY_PICK_HEAD"
		fi
		if [ "${_git_hex_cleanup_abort:-true}" = "true" ] && [ -n "${cherry_pick_head_path}" ] && [ -f "${cherry_pick_head_path}" ]; then
			git -C "${repo_path}" cherry-pick --abort >/dev/null 2>&1 || true
		fi
		# If we created an auto-stash, attempt to restore it on any unexpected early exit.
		if [ "${auto_stash:-false}" = "true" ] && [ "${stash_created:-false}" != "false" ] && [ "${stash_restore_attempted:-false}" != "true" ]; then
			stash_restore_attempted="true"
			stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
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
		read -r major minor git_version_raw <<<"$(git_hex_parse_git_version | tr '\t' ' ')"
		if [ "${major}" -lt 2 ] || { [ "${major}" -eq 2 ] && [ "${minor}" -lt 33 ]; }; then
			mcp_fail_invalid_args "Merge strategy 'ort' requires git 2.33+. Current version: ${git_version_raw}. Use 'recursive' instead."
		fi
		;;
	*)
		mcp_fail_invalid_args "Invalid merge strategy '${strategy}'. Must be one of: recursive, ort, resolve"
		;;
	esac
fi

# Validate git repository
git_hex_require_repo  "${repo_path}"

# Check if repository has any commits
if ! git -C "${repo_path}" rev-parse HEAD >/dev/null 2>&1; then
	mcp_fail_invalid_args "Repository has no commits. Nothing to cherry-pick onto."
fi

# Check for any in-progress git operations
git_dir="$( git_hex_get_git_dir "${repo_path}")"
operation="$(   git_hex_get_in_progress_operation_from_git_dir "${git_dir}")"
git_hex_require_no_in_progress_operation  "${operation}"

# Verify commit exists and resolve to full hash.
# Use --verify and ^{commit} so inputs that look like paths don't pass validation.
source_hash="$( git -C "${repo_path}" rev-parse --verify "${commit}^{commit}" 2>/dev/null || true)"
if  [ -z "${source_hash}" ]; then
	mcp_fail_invalid_args "Invalid commit ref: ${commit}"
fi

# Reject merge commits early (git cherry-pick requires -m to select a parent).
if  git -C "${repo_path}" rev-parse --verify "${source_hash}^2" >/dev/null 2>&1; then
	mcp_fail_invalid_args "Cannot cherry-pick merge commits. Use git cherry-pick -m <parent> manually."
fi

# Get source commit's subject for commitMessage
source_subject="$( git -C "${repo_path}" log -1 --format='%s' "${source_hash}" 2>/dev/null || true)"

# Handle manual auto-stash (after validating inputs to avoid leaving stashes on early failures)
stash_created="false"
stash_not_restored="false"
stash_restore_attempted="false"
if [ "${auto_stash}" = "true" ]; then
	stash_created="$(git_hex_auto_stash "${repo_path}")"
else
	if ! git -C "${repo_path}" diff --quiet -- 2>/dev/null || ! git -C "${repo_path}" diff --cached --quiet -- 2>/dev/null; then
		mcp_fail_invalid_args "Repository has uncommitted changes. Please commit or stash them first."
	fi
fi

# Save HEAD before operation for headBefore/headAfter consistency
head_before="$(git -C "${repo_path}" rev-parse HEAD)"

# Create backup ref for undo support (after validation, before mutations)
backup_ref="$( git_hex_create_backup "${repo_path}" "cherryPickSingle")"

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
		stash_restore_attempted="true"
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
			--arg backupRef "${backup_ref}" \
			--arg summary "Changes from ${source_hash:0:7} applied but not committed (staged)" \
			--arg commitMessage "${source_subject}" \
			--argjson stashNotRestored "${stash_not_restored}" \
			'{success: $success, headBefore: $headBefore, headAfter: $headAfter, sourceCommit: $sourceCommit, backupRef: $backupRef, summary: $summary, commitMessage: $commitMessage, stashNotRestored: $stashNotRestored}')"
	else
		# shellcheck disable=SC2016
		mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--argjson success true \
			--arg headBefore "${head_before}" \
			--arg headAfter "${head_after}" \
			--arg sourceCommit "${source_hash}" \
			--arg backupRef "${backup_ref}" \
			--arg summary "Cherry-picked ${source_hash:0:7} as new commit ${head_after:0:7}" \
			--arg commitMessage "${source_subject}" \
			--argjson stashNotRestored "${stash_not_restored}" \
			'{success: $success, headBefore: $headBefore, headAfter: $headAfter, sourceCommit: $sourceCommit, backupRef: $backupRef, summary: $summary, commitMessage: $commitMessage, stashNotRestored: $stashNotRestored}')"
	fi
else
	# Cherry-pick failed - cleanup will abort
	# Provide more specific error context
	if grep -qi "conflict" <<<"${pick_error}"; then
		if [ "${abort_on_conflict}" = "false" ]; then
			_git_hex_cleanup_abort="false"
			trap - EXIT
			head_after_pause="$(git -C "${repo_path}" rev-parse HEAD 2>/dev/null || echo "")"
			conflicting_json="$(git_hex_get_conflicting_files_json "${repo_path}")"
			# shellcheck disable=SC2016
			mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
				--argjson success false \
				--argjson paused true \
				--arg reason "conflict" \
				--arg headBefore "${head_before}" \
				--arg headAfter "${head_after_pause}" \
				--arg sourceCommit "${source_hash}" \
				--arg backupRef "${backup_ref}" \
				--arg commitMessage "${source_subject}" \
				--argjson conflictingFiles "${conflicting_json}" \
				--arg summary "Cherry-pick paused due to conflicts. Use getConflictStatus and resolveConflict to continue." \
				'{success: $success, paused: $paused, reason: $reason, headBefore: $headBefore, headAfter: $headAfter, sourceCommit: $sourceCommit, backupRef: $backupRef, commitMessage: $commitMessage, conflictingFiles: $conflictingFiles, summary: $summary}')"
		else
			git_dir="$(git_hex_get_git_dir "${repo_path}")"
			cherry_pick_head_path="${git_dir}/CHERRY_PICK_HEAD"
			if [ -n "${cherry_pick_head_path}" ] && [ -f "${cherry_pick_head_path}" ]; then
				git -C "${repo_path}" cherry-pick --abort >/dev/null 2>&1 || true
			fi
			if [ "${auto_stash}" = "true" ]; then
				stash_restore_attempted="true"
				stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
			fi
			mcp_fail -32603 "Cherry-pick failed due to conflicts. Repository has been restored to original state."
		fi
	elif grep -qi "gpg\\|signing\\|sign\\|hook\\|pre-commit\\|commit-msg" <<<"${pick_error}"; then
		[ "${auto_stash}" = "true" ] && stash_restore_attempted="true" && stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
		git_hex_fail_commit_error "Cherry-pick failed" "${pick_error}" " Repository has been restored to original state."
	elif grep -qi "empty" <<<"${pick_error}"; then
		[ "${auto_stash}" = "true" ] && stash_restore_attempted="true" && stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
		mcp_fail -32603 "Cherry-pick failed: The commit would be empty (changes already exist in HEAD)."
	else
		[ "${auto_stash}" = "true" ] && stash_restore_attempted="true" && stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
		error_hint="${pick_error%%$'\n'*}"
		mcp_fail -32603 "Cherry-pick failed: ${error_hint}. Repository has been restored to original state."
	fi
fi
