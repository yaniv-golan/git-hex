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
	git_hex_error "INVALID_ARGUMENT" "autoStash cannot be used with abortOnConflict=false for cherry-pick." \
		"Set autoStash=false and stash manually" \
		"Or set abortOnConflict=true to use autoStash"
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
			git_hex_error "GIT_VERSION_UNSUPPORTED" "Merge strategy 'ort' requires git 2.33+. Current version: ${git_version_raw}." \
				"Use strategy='recursive' instead" \
				"Or upgrade Git to version 2.33 or later"
		fi
		;;
	*)
		git_hex_error "INVALID_ARGUMENT" "Invalid merge strategy '${strategy}'." \
			"Valid strategies are: recursive, ort, resolve"
		;;
	esac
fi

# Validate git repository
git_hex_require_repo  "${repo_path}"

# Check if repository has any commits
if ! git -C "${repo_path}" rev-parse HEAD >/dev/null 2>&1; then
	git_hex_error "NO_COMMITS" "Repository has no commits." \
		"Create at least one commit before cherry-picking"
fi

# Check for any in-progress git operations
git_dir="$( git_hex_get_git_dir "${repo_path}")"
operation="$(   git_hex_get_in_progress_operation_from_git_dir "${git_dir}")"
git_hex_require_no_in_progress_operation  "${operation}"

# Verify commit exists and resolve to full hash.
# Use --verify and ^{commit} so inputs that look like paths don't pass validation.
source_hash="$( git -C "${repo_path}" rev-parse --verify "${commit}^{commit}" 2>/dev/null || true)"
if  [ -z "${source_hash}" ]; then
	git_hex_error "INVALID_COMMIT" "Invalid commit ref: ${commit}" \
		"Use a valid commit SHA, branch name, or tag" \
		"Use 'git log --oneline' to find valid commit references"
fi

# Reject merge commits early (git cherry-pick requires -m to select a parent).
if  git -C "${repo_path}" rev-parse --verify "${source_hash}^2" >/dev/null 2>&1; then
	git_hex_error "MERGE_COMMIT" "Cannot cherry-pick merge commits." \
		"Use 'git cherry-pick -m <parent>' manually to cherry-pick merge commits" \
		"Or cherry-pick the individual commits from the merged branch"
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
		git_hex_error "UNCOMMITTED_CHANGES" "Repository has uncommitted changes." \
			"Use autoStash=true to automatically stash and restore changes" \
			"Or commit/stash changes manually first"
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
if pick_error="$(git -C "${repo_path}" cherry-pick "${pick_args[@]}" 2>&1)"; then # bash32-safe: pick_args always contains source_hash (line 135)
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

	# Build and emit result (mcp_result_success wraps in {success: true, result: ...} envelope)
	if [ "${no_commit}" = "true" ]; then
		# shellcheck disable=SC2016
		result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--arg headBefore "${head_before}" \
			--arg headAfter "${head_after}" \
			--arg sourceCommit "${source_hash}" \
			--arg backupRef "${backup_ref}" \
			--arg summary "Changes from ${source_hash:0:7} applied but not committed (staged)" \
			--arg commitMessage "${source_subject}" \
			--argjson stashNotRestored "${stash_not_restored}" \
			'{headBefore: $headBefore, headAfter: $headAfter, sourceCommit: $sourceCommit, backupRef: $backupRef, summary: $summary, commitMessage: $commitMessage, stashNotRestored: $stashNotRestored}')"
	else
		# shellcheck disable=SC2016
		result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--arg headBefore "${head_before}" \
			--arg headAfter "${head_after}" \
			--arg sourceCommit "${source_hash}" \
			--arg backupRef "${backup_ref}" \
			--arg summary "Cherry-picked ${source_hash:0:7} as new commit ${head_after:0:7}" \
			--arg commitMessage "${source_subject}" \
			--argjson stashNotRestored "${stash_not_restored}" \
			'{headBefore: $headBefore, headAfter: $headAfter, sourceCommit: $sourceCommit, backupRef: $backupRef, summary: $summary, commitMessage: $commitMessage, stashNotRestored: $stashNotRestored}')"
	fi
	mcp_result_success "${result}"
else
	# Cherry-pick failed - cleanup will abort
	# Provide more specific error context
	if grep -qi "conflict" <<<"${pick_error}"; then
		if [ "${abort_on_conflict}" = "false" ]; then
			_git_hex_cleanup_abort="false"
			trap - EXIT
			head_after_pause="$(git -C "${repo_path}" rev-parse HEAD 2>/dev/null || echo "")"
			conflicting_json="$(git_hex_get_conflicting_files_json "${repo_path}")"
			# Cherry-pick paused - semantic failure indicated by 'paused: true' in result
			# shellcheck disable=SC2016
			result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
				--argjson paused true \
				--arg reason "conflict" \
				--arg headBefore "${head_before}" \
				--arg headAfter "${head_after_pause}" \
				--arg sourceCommit "${source_hash}" \
				--arg backupRef "${backup_ref}" \
				--arg commitMessage "${source_subject}" \
				--argjson conflictingFiles "${conflicting_json}" \
				--argjson stashNotRestored false \
				--arg summary "Cherry-pick paused due to conflicts. Use getConflictStatus and resolveConflict to continue." \
				'{paused: $paused, reason: $reason, headBefore: $headBefore, headAfter: $headAfter, sourceCommit: $sourceCommit, backupRef: $backupRef, commitMessage: $commitMessage, conflictingFiles: $conflictingFiles, stashNotRestored: $stashNotRestored, summary: $summary}')"
			mcp_result_success "${result}"
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
			git_hex_error "CHERRY_PICK_CONFLICT" "Cherry-pick failed due to conflicts. Repository has been restored to original state." \
				"Use abortOnConflict=false to pause on conflicts and resolve them manually"
		fi
	elif grep -qi "gpg\\|signing\\|sign\\|hook\\|pre-commit\\|commit-msg" <<<"${pick_error}"; then
		[ "${auto_stash}" = "true" ] && stash_restore_attempted="true" && stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
		git_hex_fail_commit_error "Cherry-pick failed" "${pick_error}" " Repository has been restored to original state."
	elif grep -qi "empty" <<<"${pick_error}"; then
		[ "${auto_stash}" = "true" ] && stash_restore_attempted="true" && stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
		git_hex_error "EMPTY_COMMIT" "Cherry-pick failed: The commit would be empty (changes already exist in HEAD)." \
			"The changes from this commit are already present in your current branch" \
			"Skip this commit or choose a different commit to cherry-pick"
	else
		[ "${auto_stash}" = "true" ] && stash_restore_attempted="true" && stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
		error_hint="${pick_error%%$'\n'*}"
		git_hex_error "CHERRY_PICK_FAILED" "Cherry-pick failed: ${error_hint}. Repository has been restored to original state." \
			"Check the error message above for details" \
			"Use 'git status' to verify repository state"
	fi
fi
