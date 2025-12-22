#!/usr/bin/env bash
set -euo pipefail

# Enable shell tracing for debugging (shows every command executed)
if [ "${GIT_HEX_DEBUG:-}" = "true" ]; then
	set -x
fi

# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/backup.sh disable=SC1091
source  "${SCRIPT_DIR}/../../lib/backup.sh"
# shellcheck source=../../lib/rebase-msg-dir.sh disable=SC1091
source  "${SCRIPT_DIR}/../../lib/rebase-msg-dir.sh"
# shellcheck source=../../lib/git-helpers.sh disable=SC1091
source  "${SCRIPT_DIR}/../../lib/git-helpers.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
onto="$(mcp_args_require '.onto')"
plan_json="$( mcp_args_get '.plan' || true)"
trimmed_plan="$(tr -d '[:space:]' <<<"${plan_json:-}")"
if  [ -z "${trimmed_plan}" ] || [ "${trimmed_plan}" = "null" ]; then
	plan_json="[]"
else
	plan_json="${plan_json:-}"
fi

plan_type="$( printf '%s' "${plan_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r 'type' 2>/dev/null || true)"
if  [ "${plan_type}" != "array" ]; then
	mcp_fail_invalid_args "plan must be an array"
fi
abort_on_conflict="$(mcp_args_bool '.abortOnConflict' --default true)"
auto_stash="$(mcp_args_bool '.autoStash' --default false)"
autosquash="$(mcp_args_bool '.autosquash' --default true)"
require_complete="$(mcp_args_bool '.requireComplete' --default false)"
sign_commits="$(mcp_args_bool '.signCommits' --default false)"

_git_hex_cleanup_files=()
_git_hex_cleanup() {
	if [ "${#_git_hex_cleanup_files[@]}" -gt 0 ]; then
		rm -f -- "${_git_hex_cleanup_files[@]}" 2>/dev/null || true
	fi
	unset GIT_HEX_TODO_FILE
	return 0
}
trap '_git_hex_cleanup' EXIT

# Validate repo
git_hex_require_repo "${repo_path}"

# Detached HEAD warning (match getRebasePlan behavior)
detached_head_warning=""
if git_hex_is_detached_head "${repo_path}"; then
	detached_head_warning=" Warning: detached HEAD; rebasing may rewrite commits without an easy branch reference."
fi

# Check HEAD exists
if ! git -C "${repo_path}" rev-parse HEAD >/dev/null 2>&1; then
	mcp_fail_invalid_args "Repository has no commits. Nothing to rebase."
fi

# Check for in-progress operations
git_dir="$(git_hex_get_git_dir "${repo_path}")"
rebase_msg_dir_marker="${git_dir}/git-hex-rebase-msg-dir"
operation_in_progress="$(  git_hex_get_in_progress_operation_from_git_dir "${git_dir}")"
git_hex_require_no_in_progress_operation  "${operation_in_progress}"

# Dirty working tree check (unless using native autostash)
if [ "${auto_stash}" = "false" ]; then
	git_hex_require_clean_worktree_tracked "${repo_path}"
fi

# Validate onto: require a commit-ish, not an arbitrary token that could be interpreted as a path.
if  ! git -C "${repo_path}" rev-parse --verify "${onto}^{commit}" >/dev/null 2>&1; then
	if git_hex_is_shallow_repo "${repo_path}"; then
		mcp_fail_invalid_args "Invalid onto ref: ${onto} (repository is shallow; try git fetch --unshallow)"
	fi
	mcp_fail_invalid_args "Invalid onto ref: ${onto}"
fi

# Get commits in range
actual_commits="$(git -C "${repo_path}" rev-list --reverse "${onto}..HEAD" 2>/dev/null || echo "")"
actual_count="$(git -C "${repo_path}" rev-list --count "${onto}..HEAD" 2>/dev/null || echo "0")"

if [ -z "${actual_commits}" ]; then
	# shellcheck disable=SC2016
	mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--argjson success true \
		--arg headBefore "$(git -C "${repo_path}" rev-parse HEAD)" \
		--arg headAfter "$(git -C "${repo_path}" rev-parse HEAD)" \
		--arg summary "Nothing to rebase - HEAD is already at ${onto}" \
		'{success: $success, headBefore: $headBefore, headAfter: $headAfter, summary: $summary}')"
	exit 0
fi

# Parse plan into arrays
plan_length="$(printf '%s' "${plan_json}" | "${MCPBASH_JSON_TOOL_BIN}" 'length' 2>/dev/null || echo "0")"
plan_actions=()
plan_commits=()
plan_messages=()

validate_rebase_action()  {
	local action="$1"
	case "${action}" in
	pick | reword | squash | fixup | drop)
		return 0
		;;
	*)
		mcp_fail_invalid_args "Invalid action '${action}'. Must be one of: pick, reword, squash, fixup, drop"
		;;
	esac
}

if  [ "${plan_length}" -gt 0 ]; then
	has_null_message="$(printf '%s' "${plan_json}" | "${MCPBASH_JSON_TOOL_BIN}" '[.[] | (.message // "") | tostring | contains("\u0000")] | any' 2>/dev/null || echo "false")"
	if [ "${has_null_message}" = "true" ]; then
		mcp_fail_invalid_args "Commit message cannot contain null bytes"
	fi
fi

use_custom_todo="true"
if [ "${plan_length}" -eq 0 ] && [ "${require_complete}" != "true" ]; then
	use_custom_todo="false"
fi

if   [ "${plan_length}" -gt 0 ]; then
	# Read plan entries with NUL delimiters so messages can contain any characters except NUL.
	# Use -j to avoid jq inserting newlines between outputs (newlines inside messages are validated below).
	while IFS= read -r -d '' action && IFS= read -r -d '' commit_ref && IFS= read -r -d '' message; do
		[ -z "${action}" ] && action="null"
		[ -z "${commit_ref}" ] && commit_ref="null"

		validate_rebase_action "${action}"

		full_hash="$(git -C "${repo_path}" rev-parse --verify "${commit_ref}^{commit}" 2>/dev/null || true)"
		if [ -z "${full_hash}" ]; then
			mcp_fail_invalid_args "Invalid commit reference: ${commit_ref}"
		fi
		if ! grep -Fxq -- "${full_hash}" <<<"${actual_commits}"; then
			mcp_fail_invalid_args "Commit ${commit_ref} (${full_hash:0:7}) not in rebase range ${onto}..HEAD"
		fi
		# Check for duplicates (use ${array[@]+"${array[@]}"} pattern for set -u safety)
		for existing in ${plan_commits[@]+"${plan_commits[@]}"}; do
			if [ "${existing}" = "${full_hash}" ]; then
				mcp_fail_invalid_args "Duplicate commit in plan: ${commit_ref}"
			fi
		done
		if [ -n "${message}" ] && { [[ "${message}" == *$'\t'* ]] || [[ "${message}" == *$'\n'* ]]; }; then
			mcp_fail_invalid_args "Commit message cannot contain TAB or newline characters"
		fi
		if [ "${action}" = "reword" ] && [ -z "${message}" ]; then
			mcp_fail_invalid_args "Action 'reword' requires a 'message' field. Use 'pick' to keep original message."
		fi
		plan_actions+=("${action}")
		plan_commits+=("${full_hash}")
		plan_messages+=("${message}")
	done < <(
		printf '%s' "${plan_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r -j \
			'.[] | (.action | tostring) + "\u0000" + (.commit | tostring) + "\u0000" + ((.message // "") | tostring) + "\u0000"'
	)
fi

if [ "${require_complete}" = "true" ]; then
	if [ "${plan_length}" -ne "${actual_count}" ]; then
		mcp_fail_invalid_args "Plan has ${plan_length} commits but range has ${actual_count}. All commits must be included (use 'drop' to remove)."
	fi
fi

# Create a directory for message files (avoids shell escaping issues entirely)
# Each reword/fixup message is written to a file and read with git commit -F
# NOTE: These files must persist until the rebase completes (they are referenced by exec commands).
# The path is persisted under `.git/` so `continueOperation`/`abortOperation` can clean it up.
_git_hex_msg_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.rebase.msg.XXXXXX")"
_git_hex_msg_counter=0
printf '%s\n' "${_git_hex_msg_dir}" >"${rebase_msg_dir_marker}" 2>/dev/null || true

# Helper to create a message file and return exec command
# Uses git commit -F to avoid shell escaping issues with special characters
create_reword_exec()  {
	local msg="$1"
	local msg_file="${_git_hex_msg_dir}/msg_${_git_hex_msg_counter}"
	_git_hex_msg_counter=$((_git_hex_msg_counter + 1))
	printf '%s' "${msg}" >"${msg_file}"
	if [ "${sign_commits}" = "true" ]; then
		printf 'exec git commit --amend -F %q\n' "${msg_file}"
	else
		printf 'exec git commit --amend --no-gpg-sign -F %q\n' "${msg_file}"
	fi
}

complete_todo=""

if  [ "${require_complete}" = "true" ]; then
	for ((i = 0; i < plan_length; i++)); do
		action="${plan_actions[$i]}"
		commit_hash="${plan_commits[$i]}"
		message="${plan_messages[$i]}"
		subject="$(git -C "${repo_path}" log -1 --format='%s' "${commit_hash}")"

		if [ -n "${message}" ] && [ "${action}" = "reword" ]; then
			complete_todo="${complete_todo}pick ${commit_hash} ${subject}
	$(create_reword_exec "${message}")
	"
		elif [ -n "${message}" ] && [ "${action}" = "fixup" ]; then
			complete_todo="${complete_todo}fixup ${commit_hash} ${subject}
	$(create_reword_exec "${message}")
	"
		elif [ -n "${message}" ] && [ "${action}" = "squash" ]; then
			complete_todo="${complete_todo}squash ${commit_hash} ${subject}
	$(create_reword_exec "${message}")
	"
		else
			validate_rebase_action "${action}"
			complete_todo="${complete_todo}${action} ${commit_hash} ${subject}
	"
		fi
	done
else
	plan_actions_file="$(mktemp "${TMPDIR:-/tmp}/githex.rebase.actions.XXXXXX")"
	plan_messages_file="$(mktemp "${TMPDIR:-/tmp}/githex.rebase.messages.XXXXXX")"
	# These action/message index files CAN be cleaned up (they're read before rebase starts)
	# But _git_hex_msg_dir must NOT be cleaned up (exec commands read from it during rebase)
	_git_hex_cleanup_files+=("${plan_actions_file}" "${plan_messages_file}")

	if [ "${plan_length}" -gt 0 ]; then
		for ((i = 0; i < plan_length; i++)); do
			printf '%s\t%s\n' "${plan_commits[$i]}" "${plan_actions[$i]}" >>"${plan_actions_file}"
			if [ -n "${plan_messages[$i]}" ]; then
				printf '%s\t%s\n' "${plan_commits[$i]}" "${plan_messages[$i]}" >>"${plan_messages_file}"
			fi
		done
	fi

	while IFS= read -r commit_hash; do
		action_line="$(grep "^${commit_hash}"$'\t' "${plan_actions_file}" 2>/dev/null || true)"
		if [ -n "${action_line}" ]; then
			action="${action_line#*$'\t'}"
			message_line="$(grep "^${commit_hash}"$'\t' "${plan_messages_file}" 2>/dev/null || true)"
			message="${message_line#*$'\t'}"
			[ "${message_line}" = "${message}" ] && message=""
		else
			action="pick"
			message=""
		fi

		validate_rebase_action "${action}"

		if [ "${action}" = "reword" ] && [ -z "${message}" ]; then
			mcp_fail_invalid_args "Action 'reword' requires a 'message' field. Use 'pick' to keep original message."
		fi

		subject="$(git -C "${repo_path}" log -1 --format='%s' "${commit_hash}")"

		if [ -n "${message}" ] && [ "${action}" = "reword" ]; then
			complete_todo="${complete_todo}pick ${commit_hash} ${subject}
	$(create_reword_exec "${message}")
	"
		elif [ -n "${message}" ] && [ "${action}" = "fixup" ]; then
			complete_todo="${complete_todo}fixup ${commit_hash} ${subject}
	$(create_reword_exec "${message}")
	"
		elif [ -n "${message}" ] && [ "${action}" = "squash" ]; then
			complete_todo="${complete_todo}squash ${commit_hash} ${subject}
	$(create_reword_exec "${message}")
	"
		else
			complete_todo="${complete_todo}${action} ${commit_hash} ${subject}
	"
		fi
	done <<<"${actual_commits}"
fi

# Create todo file and sequence editor command
if [ "${use_custom_todo}" = "true" ]; then
	todo_file="$(mktemp "${TMPDIR:-/tmp}/githex.rebase.todo.XXXXXX")"
	printf '%s' "${complete_todo}" >"${todo_file}"
	# Export the todo file path so the sequence editor can access it
	# This avoids quoting issues with paths containing special characters
	export GIT_HEX_TODO_FILE="${todo_file}"
	# shellcheck disable=SC2016 # Variables must expand at runtime, not parse time
	seq_editor='sh -c '\''cat "$GIT_HEX_TODO_FILE" > "$1"'\'' --'

	_git_hex_cleanup_files+=("${todo_file}")
else
	seq_editor=""
fi

# Backup before mutating
head_before="$( git -C "${repo_path}" rev-parse HEAD)"
backup_ref="$( git_hex_create_backup "${repo_path}" "rebaseWithPlan")"

rebase_args=("-i")
if [ "${autosquash}" = "true" ]; then
	rebase_args+=("--autosquash")
else
	rebase_args+=("--no-autosquash")
fi
if [ "${auto_stash}" = "true" ]; then
	rebase_args+=("--autostash")
fi

rebase_output=""
rebase_status=0
if  [ "${use_custom_todo}" = "true" ]; then
	if [ "${sign_commits}" = "true" ]; then
		rebase_output="$(GIT_SEQUENCE_EDITOR="${seq_editor}" GIT_EDITOR=true git -C "${repo_path}" rebase "${rebase_args[@]}" "${onto}" 2>&1)" || rebase_status=$? # bash32-safe: rebase_args always contains -i (line 294)
	else
		rebase_output="$(GIT_SEQUENCE_EDITOR="${seq_editor}" GIT_EDITOR=true git -c commit.gpgsign=false -C "${repo_path}" rebase "${rebase_args[@]}" "${onto}" 2>&1)" || rebase_status=$? # bash32-safe: rebase_args always contains -i (line 294)
	fi
else
	if [ "${sign_commits}" = "true" ]; then
		rebase_output="$(GIT_SEQUENCE_EDITOR=true git -C "${repo_path}" rebase "${rebase_args[@]}" "${onto}" 2>&1)" || rebase_status=$? # bash32-safe: rebase_args always contains -i (line 294)
	else
		rebase_output="$(GIT_SEQUENCE_EDITOR=true git -c commit.gpgsign=false -C "${repo_path}" rebase "${rebase_args[@]}" "${onto}" 2>&1)" || rebase_status=$? # bash32-safe: rebase_args always contains -i (line 294)
	fi
fi

# Debug output (always on failure, or when explicitly enabled)
if [ "${GIT_HEX_DEBUG_REBASE:-}" = "true" ] || [ "${rebase_status}" -ne 0 ]; then
	printf 'DEBUG rebase_status=%s\n' "${rebase_status}" >&2
	printf 'DEBUG rebase_output=%s\n' "${rebase_output}" >&2
	if [ "${use_custom_todo}" = "true" ] && [ -f "${todo_file:-}" ]; then
		printf 'DEBUG todo_file contents:\n%s\n' "$(cat "${todo_file}")" >&2
	fi
fi

if [ "${rebase_status}" -eq 0 ]; then
	head_after="$(git -C "${repo_path}" rev-parse HEAD)"
	# Record post-operation state for undo safety checks
	git_hex_record_last_head "${repo_path}" "${head_after}"
	_git_hex_cleanup_rebase_msg_dir "${rebase_msg_dir_marker}"
	# shellcheck disable=SC2016
	mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--argjson success true \
		--argjson paused false \
		--arg headBefore "${head_before}" \
		--arg headAfter "${head_after}" \
		--arg backupRef "${backup_ref}" \
		--argjson commitsRebased "${actual_count}" \
		--arg summary "Rebased ${actual_count} commit(s) onto ${onto}.${detached_head_warning}" \
		'{success: $success, paused: $paused, headBefore: $headBefore, headAfter: $headAfter, backupRef: $backupRef, commitsRebased: $commitsRebased, summary: $summary}')"
	exit 0
else
	rebase_merge_dir="$(git -C "${repo_path}" rev-parse --git-path rebase-merge 2>/dev/null || true)"
	rebase_apply_dir="$(git -C "${repo_path}" rev-parse --git-path rebase-apply 2>/dev/null || true)"
	rebase_in_progress="false"
	if [ -n "${rebase_merge_dir}" ] && [ -d "${rebase_merge_dir}" ]; then
		rebase_in_progress="true"
	elif [ -n "${rebase_apply_dir}" ] && [ -d "${rebase_apply_dir}" ]; then
		rebase_in_progress="true"
	fi

	has_unmerged="false"
	if IFS= read -r -d '' _ < <(git -C "${repo_path}" diff --name-only --diff-filter=U -z 2>/dev/null || true); then
		has_unmerged="true"
	fi

	if [ "${has_unmerged}" = "true" ] || { [ "${rebase_in_progress}" = "true" ] && grep -qE '(^|\n)CONFLICT' <<<"${rebase_output}"; }; then
		if [ "${abort_on_conflict}" = "false" ]; then
			conflicting_json="$(git_hex_get_conflicting_files_json "${repo_path}")"
			head_after_pause="$(git -C "${repo_path}" rev-parse HEAD)"
			# shellcheck disable=SC2016
			mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
				--argjson success false \
				--argjson paused true \
				--arg reason "conflict" \
				--arg headBefore "${head_before}" \
				--arg headAfter "${head_after_pause}" \
				--arg backupRef "${backup_ref}" \
				--argjson conflictingFiles "${conflicting_json}" \
				--arg summary "Rebase paused due to conflicts. Use getConflictStatus for details.${detached_head_warning}" \
				'{success: $success, paused: $paused, reason: $reason, headBefore: $headBefore, headAfter: $headAfter, backupRef: $backupRef, conflictingFiles: $conflictingFiles, summary: $summary}')"
			exit 0
		else
			git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
			_git_hex_cleanup_rebase_msg_dir "${rebase_msg_dir_marker}"
			mcp_fail -32603 "Rebase failed due to conflicts. Repository has been restored to original state."
		fi
	elif [ "${rebase_in_progress}" = "true" ]; then
		# Rebase stopped for a non-conflict reason (e.g., hooks, missing editor, exec failure).
		# Do not abort: leave state for manual intervention and allow continueOperation/abortOperation.
		head_after_pause="$(git -C "${repo_path}" rev-parse HEAD 2>/dev/null || echo "")"
		error_hint="${rebase_output%%$'\n'*}"
		if [ -z "${error_hint}" ]; then
			error_hint="Rebase stopped"
		fi
		# shellcheck disable=SC2016
		mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--argjson success false \
			--argjson paused true \
			--arg reason "stopped" \
			--arg headBefore "${head_before}" \
			--arg headAfter "${head_after_pause}" \
			--arg backupRef "${backup_ref}" \
			--argjson conflictingFiles "[]" \
			--arg summary "Rebase paused (non-conflict stop): ${error_hint}.${detached_head_warning}" \
			'{success: $success, paused: $paused, reason: $reason, headBefore: $headBefore, headAfter: $headAfter, backupRef: $backupRef, conflictingFiles: $conflictingFiles, summary: $summary}')"
		exit 0
	elif grep -qi "nothing to do" <<<"${rebase_output}"; then
		git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
		_git_hex_cleanup_rebase_msg_dir "${rebase_msg_dir_marker}"
		mcp_fail_invalid_args "Nothing to rebase"
	else
		git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
		_git_hex_cleanup_rebase_msg_dir "${rebase_msg_dir_marker}"
		error_hint="${rebase_output%%$'\n'*}"
		mcp_fail -32603 "Rebase failed: ${error_hint}"
	fi
fi
