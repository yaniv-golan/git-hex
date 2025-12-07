#!/usr/bin/env bash
set -euo pipefail

# Enable shell tracing for debugging (shows every command executed)
if [ "${GIT_HEX_DEBUG:-}" = "true" ]; then
	set -x
fi

# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/backup.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/backup.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
onto="$(mcp_args_require '.onto')"
plan_json="$(mcp_args_get '.plan' || true)"
trimmed_plan="$(echo "${plan_json:-}" | tr -d '[:space:]')"
if [ -z "${trimmed_plan}" ] || [ "${trimmed_plan}" = "null" ]; then
	plan_json="[]"
else
	plan_json="${plan_json:-}"
fi
abort_on_conflict="$(mcp_args_bool '.abortOnConflict' --default true)"
auto_stash="$(mcp_args_bool '.autoStash' --default false)"
autosquash="$(mcp_args_bool '.autosquash' --default true)"
require_complete="$(mcp_args_bool '.requireComplete' --default false)"

# Validate repo
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

# Check HEAD exists
if ! git -C "${repo_path}" rev-parse HEAD >/dev/null 2>&1; then
	mcp_fail_invalid_args "Repository has no commits. Nothing to rebase."
fi

# Check for in-progress operations
if [ -d "${repo_path}/.git/rebase-merge" ] || [ -d "${repo_path}/.git/rebase-apply" ]; then
	mcp_fail_invalid_args "Repository is in a rebase state. Please resolve or abort it first."
fi
if [ -f "${repo_path}/.git/CHERRY_PICK_HEAD" ]; then
	mcp_fail_invalid_args "Repository is in a cherry-pick state. Please resolve or abort it first."
fi
if [ -f "${repo_path}/.git/MERGE_HEAD" ]; then
	mcp_fail_invalid_args "Repository is in a merge state. Please resolve or abort it first."
fi

# Dirty working tree check (unless using native autostash)
if [ "${auto_stash}" = "false" ]; then
	if ! git -C "${repo_path}" diff-index --quiet HEAD -- 2>/dev/null; then
		mcp_fail_invalid_args "Repository has uncommitted changes. Please commit or stash them first."
	fi
fi

# Validate onto
if ! git -C "${repo_path}" rev-parse "${onto}" >/dev/null 2>&1; then
	mcp_fail_invalid_args "Invalid onto ref: ${onto}"
fi

# Get commits in range
actual_commits="$(git -C "${repo_path}" rev-list --reverse "${onto}..HEAD" 2>/dev/null || echo "")"
actual_count="$(echo "${actual_commits}" | wc -l | tr -d ' ')"

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
plan_length="$(echo "${plan_json}" | "${MCPBASH_JSON_TOOL_BIN}" 'length' 2>/dev/null || echo "0")"
plan_actions=()
plan_commits=()
plan_messages=()

if [ "${plan_length}" -gt 0 ]; then
	has_null_message="$(echo "${plan_json}" | "${MCPBASH_JSON_TOOL_BIN}" '[.[] | (.message // "") | tostring | contains("\u0000")] | any' 2>/dev/null || echo "false")"
	if [ "${has_null_message}" = "true" ]; then
		mcp_fail_invalid_args "Commit message cannot contain null bytes"
	fi
fi

use_custom_todo="true"
if [ "${plan_length}" -eq 0 ] && [ "${require_complete}" != "true" ]; then
	use_custom_todo="false"
fi

if [ "${plan_length}" -gt 0 ]; then
	for i in $(seq 0 $((plan_length - 1))); do
		action="$(echo "${plan_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i].action")"
		commit_ref="$(echo "${plan_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i].commit")"
		message="$(echo "${plan_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i].message // \"\"")"

		full_hash="$(git -C "${repo_path}" rev-parse --verify "${commit_ref}^{commit}" 2>/dev/null || true)"
		if [ -z "${full_hash}" ]; then
			mcp_fail_invalid_args "Invalid commit reference: ${commit_ref}"
		fi
		if ! echo "${actual_commits}" | grep -qx "${full_hash}"; then
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
	done
fi

if [ "${require_complete}" = "true" ]; then
	if [ "${plan_length}" -ne "${actual_count}" ]; then
		mcp_fail_invalid_args "Plan has ${plan_length} commits but range has ${actual_count}. All commits must be included (use 'drop' to remove)."
	fi
fi

# Helper to escape single quotes for embedding in single-quoted strings
# Replaces ' with '\'' (end quote, escaped quote, start quote)
escape_message() {
	local msg="$1"
	printf '%s' "${msg//\'/\'\\\'\'}"
}

complete_todo=""

if [ "${require_complete}" = "true" ]; then
	for i in $(seq 0 $((plan_length - 1))); do
		action="${plan_actions[$i]}"
		commit_hash="${plan_commits[$i]}"
		message="${plan_messages[$i]}"
		subject="$(git -C "${repo_path}" log -1 --format='%s' "${commit_hash}")"

		if [ -n "${message}" ] && [ "${action}" = "reword" ]; then
			escaped_message="$(escape_message "${message}")"
			complete_todo="${complete_todo}pick ${commit_hash} ${subject}
exec sh -c 'git commit --amend -m \"\$1\"' _ '${escaped_message}'
"
		elif [ -n "${message}" ] && { [ "${action}" = "squash" ] || [ "${action}" = "fixup" ]; }; then
			escaped_message="$(escape_message "${message}")"
			complete_todo="${complete_todo}fixup ${commit_hash} ${subject}
exec sh -c 'git commit --amend -m \"\$1\"' _ '${escaped_message}'
"
		else
			complete_todo="${complete_todo}${action} ${commit_hash} ${subject}
"
		fi
	done
else
	plan_actions_file="$(mktemp)"
	plan_messages_file="$(mktemp)"
	_git_hex_prev_exit_trap="$(trap -p EXIT | sed -E "s/trap -- '(.*)' EXIT/\1/" || true)"
	_git_hex_cleanup_files="${plan_actions_file} ${plan_messages_file}"
	_git_hex_cleanup() {
		# shellcheck disable=SC2086
		rm -f ${_git_hex_cleanup_files} 2>/dev/null || true
		[ -n "${_git_hex_prev_exit_trap}" ] && eval "${_git_hex_prev_exit_trap}"
		return 0
	}
	trap '_git_hex_cleanup' EXIT

	if [ "${plan_length}" -gt 0 ]; then
		for i in $(seq 0 $((plan_length - 1))); do
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

		if [ "${action}" = "reword" ] && [ -z "${message}" ]; then
			mcp_fail_invalid_args "Action 'reword' requires a 'message' field. Use 'pick' to keep original message."
		fi

		subject="$(git -C "${repo_path}" log -1 --format='%s' "${commit_hash}")"

		if [ -n "${message}" ] && [ "${action}" = "reword" ]; then
			escaped_message="$(escape_message "${message}")"
			complete_todo="${complete_todo}pick ${commit_hash} ${subject}
exec sh -c 'git commit --amend -m \"\$1\"' _ '${escaped_message}'
"
		elif [ -n "${message}" ] && { [ "${action}" = "squash" ] || [ "${action}" = "fixup" ]; }; then
			escaped_message="$(escape_message "${message}")"
			complete_todo="${complete_todo}fixup ${commit_hash} ${subject}
exec sh -c 'git commit --amend -m \"\$1\"' _ '${escaped_message}'
"
		else
			complete_todo="${complete_todo}${action} ${commit_hash} ${subject}
"
		fi
	done <<<"${actual_commits}"
fi

# Create todo file and sequence editor command
if [ "${use_custom_todo}" = "true" ]; then
	todo_file="$(mktemp)"
	printf '%s' "${complete_todo}" >"${todo_file}"
	# Export the todo file path so the sequence editor can access it
	# This avoids quoting issues with paths containing special characters
	export GIT_HEX_TODO_FILE="${todo_file}"
	# shellcheck disable=SC2016 # Variables must expand at runtime, not parse time
	seq_editor='sh -c '\''cat "$GIT_HEX_TODO_FILE" > "$1"'\'' --'

	# Cleanup temp files on exit
	if [ -n "${_git_hex_cleanup_files:-}" ]; then
		_git_hex_cleanup_files="${_git_hex_cleanup_files} ${todo_file}"
	else
		_git_hex_prev_exit_trap="$(trap -p EXIT | sed -E "s/trap -- '(.*)' EXIT/\1/" || true)"
		_git_hex_cleanup_files="${todo_file}"
		_git_hex_cleanup() {
			# shellcheck disable=SC2086
			rm -f ${_git_hex_cleanup_files} 2>/dev/null || true
			unset GIT_HEX_TODO_FILE
			[ -n "${_git_hex_prev_exit_trap}" ] && eval "${_git_hex_prev_exit_trap}"
			return 0
		}
		trap '_git_hex_cleanup' EXIT
	fi
else
	seq_editor=""
fi

# Backup before mutating
head_before="$(git -C "${repo_path}" rev-parse HEAD)"
git_hex_create_backup "${repo_path}" "rebaseWithPlan" >/dev/null

rebase_args=("-i")
if [ "${autosquash}" = "true" ]; then
	rebase_args+=("--autosquash")
fi
if [ "${auto_stash}" = "true" ]; then
	rebase_args+=("--autostash")
fi

rebase_output=""
rebase_status=0
if [ "${use_custom_todo}" = "true" ]; then
	rebase_output="$(GIT_SEQUENCE_EDITOR="${seq_editor}" git -C "${repo_path}" rebase "${rebase_args[@]}" "${onto}" 2>&1)" || rebase_status=$?
else
	rebase_output="$(GIT_SEQUENCE_EDITOR=true git -C "${repo_path}" rebase "${rebase_args[@]}" "${onto}" 2>&1)" || rebase_status=$?
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
	# shellcheck disable=SC2016
	mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--argjson success true \
		--argjson paused false \
		--arg headBefore "${head_before}" \
		--arg headAfter "${head_after}" \
		--argjson commitsRebased "${actual_count}" \
		--arg summary "Rebased ${actual_count} commit(s) onto ${onto}" \
		'{success: $success, paused: $paused, headBefore: $headBefore, headAfter: $headAfter, commitsRebased: $commitsRebased, summary: $summary}')"
	exit 0
else
	if echo "${rebase_output}" | grep -qi "conflict"; then
		if [ "${abort_on_conflict}" = "false" ]; then
			conflicting_files="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"
			conflicting_json="[]"
			while IFS= read -r cf; do
				[ -z "${cf}" ] && continue
				# shellcheck disable=SC2016
				conflicting_json="$(echo "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
			done <<<"${conflicting_files}"
			head_after_pause="$(git -C "${repo_path}" rev-parse HEAD)"
			# shellcheck disable=SC2016
			mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
				--argjson success false \
				--argjson paused true \
				--arg reason "conflict" \
				--arg headBefore "${head_before}" \
				--arg headAfter "${head_after_pause}" \
				--argjson conflictingFiles "${conflicting_json}" \
				--arg summary "Rebase paused due to conflicts. Use getConflictStatus for details." \
				'{success: $success, paused: $paused, reason: $reason, headBefore: $headBefore, headAfter: $headAfter, conflictingFiles: $conflictingFiles, summary: $summary}')"
			exit 0
		else
			git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
			mcp_fail -32603 "Rebase failed due to conflicts. Repository has been restored to original state."
		fi
	elif echo "${rebase_output}" | grep -qi "nothing to do"; then
		git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
		mcp_fail_invalid_args "Nothing to rebase"
	else
		git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
		error_hint="$(echo "${rebase_output}" | head -1)"
		mcp_fail -32603 "Rebase failed: ${error_hint}"
	fi
fi
