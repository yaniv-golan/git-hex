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
# shellcheck source=../../lib/git-helpers.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/git-helpers.sh"
# shellcheck source=../../lib/stash.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/stash.sh"

cleanup() {
	rm -f "${_git_hex_split_cleanup_files:-}" 2>/dev/null || true
	rm -rf "${_git_hex_split_cleanup_dirs:-}" 2>/dev/null || true
	if [ "${_git_hex_abort_rebase:-false}" = "true" ] && [ "${_git_hex_rebase_started:-false}" = "true" ]; then
		git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
	fi
	return 0
}
_git_hex_abort_rebase="true"
_git_hex_rebase_started="false"
trap cleanup EXIT

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
commit_ref="$(mcp_args_require '.commit')"
splits_json="$(mcp_args_get '.splits')"
trimmed_splits="$(tr -d '[:space:]' <<<"${splits_json:-}")"
if [ -z "${trimmed_splits}" ] || [ "${trimmed_splits}" = "null" ]; then
	splits_json="[]"
else
	splits_json="${splits_json:-}"
fi

splits_type="$(printf '%s' "${splits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r 'type' 2>/dev/null || true)"
if [ "${splits_type}" != "array" ]; then
	mcp_fail_invalid_args "splits must be an array"
fi
auto_stash="$(mcp_args_bool '.autoStash' --default false)"
sign_commits="$(mcp_args_bool '.signCommits' --default false)"

git_hex_require_repo "${repo_path}"

git_dir="$(git_hex_get_git_dir "${repo_path}")"
rebase_merge_dir="${git_dir}/rebase-merge"
rebase_apply_dir="${git_dir}/rebase-apply"
operation="$(git_hex_get_in_progress_operation_from_git_dir "${git_dir}")"
case "${operation}" in
rebase) mcp_fail_invalid_args "Cannot split commit while rebase is in progress" ;;
cherry-pick) mcp_fail_invalid_args "Cannot split commit while cherry-pick is in progress" ;;
revert) mcp_fail_invalid_args "Cannot split commit while revert is in progress" ;;
merge) mcp_fail_invalid_args "Cannot split commit while merge is in progress" ;;
bisect) mcp_fail_invalid_args "Cannot split commit while bisect is in progress" ;;
esac

# Resolve commit
full_commit="$(git -C "${repo_path}" rev-parse --verify "${commit_ref}^{commit}" 2>/dev/null || true)"
if [ -z "${full_commit}" ]; then
	mcp_fail_invalid_args "Invalid commit: ${commit_ref}"
fi

# Commit must not be merge commit
if git -C "${repo_path}" rev-parse --verify "${full_commit}^2" >/dev/null 2>&1; then
	mcp_fail_invalid_args "Cannot split merge commits"
fi

# Commit must not be root commit
if ! git -C "${repo_path}" rev-parse "${full_commit}^" >/dev/null 2>&1; then
	mcp_fail_invalid_args "Cannot split root commit"
fi

# Commit must be ancestor of HEAD
if ! git -C "${repo_path}" merge-base --is-ancestor "${full_commit}" HEAD 2>/dev/null; then
	mcp_fail_invalid_args "Commit ${commit_ref} is not an ancestor of HEAD; cannot split from this branch"
fi

# Validate splits array
split_count="$(printf '%s' "${splits_json}" | "${MCPBASH_JSON_TOOL_BIN}" 'length' 2>/dev/null || echo "0")"
if [ "${split_count}" -lt 2 ]; then
	mcp_fail_invalid_args "At least 2 splits required"
fi

original_files="$(git -C "${repo_path}" diff-tree --no-commit-id --name-only -r "${full_commit}" --)"
if [ -z "${original_files}" ]; then
	mcp_fail_invalid_args "Commit ${commit_ref} has no file changes"
fi

# Read original files as JSON array (NUL-delimited, converted via jq).
# Avoids process substitution and read -d '' which have macOS CI issues.
original_files_json="$(git -C "${repo_path}" diff-tree --no-commit-id --name-only -r -z "${full_commit}" -- 2>/dev/null | "${MCPBASH_JSON_TOOL_BIN}" -Rs 'split("\u0000") | map(select(length > 0))' 2>/dev/null || echo "[]")"
original_files_count="$(printf '%s' "${original_files_json}" | "${MCPBASH_JSON_TOOL_BIN}" 'length' 2>/dev/null || echo "0")"
original_files_arr=()
for ((i = 0; i < original_files_count; i++)); do
	f="$(printf '%s' "${original_files_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i]" 2>/dev/null || true)"
	[ -z "${f}" ] && continue
	original_files_arr+=("${f}")
done

if [ "${#original_files_arr[@]}" -eq 0 ]; then
	mcp_fail_invalid_args "Commit ${commit_ref} has no file changes"
fi

array_contains() {
	local needle="$1"
	shift
	# Handle empty array case explicitly (bash 3.2 compatibility)
	if [ $# -eq 0 ]; then
		return 1
	fi
	local item
	for item in "$@"; do
		if [ "${item}" = "${needle}" ]; then
			return 0
		fi
	done
	return 1
}

# Validate coverage
covered_files_arr=()
for ((i = 0; i < split_count; i++)); do
	message="$(printf '%s' "${splits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i].message // \"\"" 2>/dev/null || true)"
	case "${message}" in
	*$'\n'* | *$'\t'*)
		mcp_fail_invalid_args "Split message cannot contain TAB or newline"
		;;
	esac

	split_files_stream="$(printf '%s' "${splits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i].files // [] | (length|tostring), .[]" 2>/dev/null || printf '0\n')"
	split_files_len="0"
	line_index=0
	while IFS= read -r file_line; do
		if [ "${line_index}" -eq 0 ]; then
			split_files_len="${file_line:-0}"
			line_index=1
			continue
		fi

		file="${file_line}"
		[ -z "${file}" ] && continue
		git_hex_require_safe_repo_relative_path "${file}"
		if ! array_contains "${file}" "${original_files_arr[@]}"; then
			mcp_fail_invalid_args "File '${file}' not in original commit"
		fi
		# Check for duplicate - use ${arr[@]+"${arr[@]}"} pattern for bash 3.2 empty array safety
		if [ "${#covered_files_arr[@]}" -gt 0 ] && array_contains "${file}" "${covered_files_arr[@]}"; then
			mcp_fail_invalid_args "File '${file}' appears in multiple splits"
		fi
		covered_files_arr+=("${file}")
	done <<<"${split_files_stream}"

	if [ "${split_files_len}" -eq 0 ]; then
		mcp_fail_invalid_args "Split $((i + 1)) has no files"
	fi
done

for file in "${original_files_arr[@]}"; do
	[ -z "${file}" ] && continue
	if ! array_contains "${file}" "${covered_files_arr[@]}"; then
		mcp_fail_invalid_args "File '${file}' from original commit not assigned to any split"
	fi
done

# Handle auto-stash
stash_created="false"
stash_not_restored="false"
if [ "${auto_stash}" = "true" ]; then
	stash_created="$(git_hex_auto_stash "${repo_path}")"
fi

# Backup ref
backup_ref="$(git_hex_create_backup "${repo_path}" "splitCommit")"

commit_parent="$(git -C "${repo_path}" rev-parse "${full_commit}^")"
commit_subject="$(git -C "${repo_path}" log -1 --format='%s' "${full_commit}")"

seq_editor="$(mktemp "${TMPDIR:-/tmp}/githex.split.seq-editor.XXXXXX")"
msg_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.split.msg.XXXXXX")"
_git_hex_split_cleanup_files="${seq_editor}"
_git_hex_split_cleanup_dirs="${msg_dir}"

cat >"${seq_editor}" <<'EDITOR_SCRIPT'
#!/usr/bin/env bash
set -e
todo_file="$1"
target_full="${GIT_HEX_TARGET_FULL}"
target_subject="${GIT_HEX_TARGET_SUBJECT}"
repo_path="${GIT_HEX_REPO_PATH}"
found=""
while IFS= read -r line; do
	if [ -z "${found}" ]; then
		IFS=' ' read -r action hash rest <<<"${line}"
		if [ "${action}" = "pick" ] && [ -n "${hash}" ]; then
			resolved_hash="$(git -C "${repo_path}" rev-parse --verify "${hash}^{commit}" 2>/dev/null || true)"
			if [ -n "${resolved_hash}" ] && [ "${resolved_hash}" = "${target_full}" ]; then
				echo "edit ${target_full} ${target_subject}"
				found="true"
				continue
			fi
		fi
	fi
	echo "${line}"
done < "${todo_file}" > "${todo_file}.tmp"
if [ -z "${found}" ]; then
	echo "ERROR: Could not find target commit ${target_full}" >&2
	exit 1
fi
mv "${todo_file}.tmp" "${todo_file}"
EDITOR_SCRIPT
chmod +x "${seq_editor}"

export GIT_HEX_TARGET_FULL="${full_commit}"
export GIT_HEX_TARGET_SUBJECT="${commit_subject}"
export GIT_HEX_REPO_PATH="${repo_path}"

_git_hex_rebase_started="true"
rebase_status=0
# shellcheck disable=SC2034
if [ "${sign_commits}" = "true" ]; then
	rebase_output="$(GIT_SEQUENCE_EDITOR="${seq_editor}" git -C "${repo_path}" rebase -i "${commit_parent}" 2>&1)" || rebase_status=$?
else
	rebase_output="$(GIT_SEQUENCE_EDITOR="${seq_editor}" git -c commit.gpgsign=false -C "${repo_path}" rebase -i "${commit_parent}" 2>&1)" || rebase_status=$?
fi

unset GIT_HEX_TARGET_FULL GIT_HEX_TARGET_SUBJECT GIT_HEX_REPO_PATH

if { [ -z "${rebase_merge_dir}" ] || [ ! -d "${rebase_merge_dir}" ]; } && { [ -z "${rebase_apply_dir}" ] || [ ! -d "${rebase_apply_dir}" ]; }; then
	# Rebase did not pause as expected
	if [ "${auto_stash}" = "true" ]; then
		git_hex_restore_stash "${repo_path}" "${stash_created}" >/dev/null
	fi
	error_hint="${rebase_output%%$'\n'*}"
	if [ -z "${error_hint}" ]; then
		error_hint="Commit ${commit_ref} not in rebase range or rebase failed"
	fi
	if [ "${rebase_status}" -ne 0 ]; then
		mcp_fail_invalid_args "Rebase failed before split: ${error_hint}"
	else
		mcp_fail_invalid_args "${error_hint}"
	fi
fi

# Reset state to unstage everything
git -C "${repo_path}" reset HEAD^ --soft >/dev/null 2>&1
git -C "${repo_path}" reset HEAD >/dev/null 2>&1

new_commits_json="[]"
for ((i = 0; i < split_count; i++)); do
	split_files_json="$(printf '%s' "${splits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -c ".[$i].files // []" 2>/dev/null || echo "[]")"
	message="$(printf '%s' "${splits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i].message" 2>/dev/null || true)"
	msg_file="${msg_dir}/msg_${i}.txt"
	printf '%s\n' "${message}" >"${msg_file}"
	# Iterate files using JSON index (avoids process substitution issues on macOS CI)
	file_count="$(printf '%s' "${split_files_json}" | "${MCPBASH_JSON_TOOL_BIN}" 'length' 2>/dev/null || echo "0")"
	for ((j = 0; j < file_count; j++)); do
		file="$(printf '%s' "${split_files_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$j]" 2>/dev/null || true)"
		[ -z "${file}" ] && continue
		git_hex_require_safe_repo_relative_path "${file}"
		git -C "${repo_path}" add -- "${file}"
	done
	commit_error=""
	if [ "${sign_commits}" = "true" ]; then
		if ! commit_error="$(git -C "${repo_path}" commit -F "${msg_file}" 2>&1)"; then
			error_hint="${commit_error%%$'\n'*}"
			mcp_fail -32603 "Failed to create split commit $((i + 1))/${split_count}: ${error_hint}"
		fi
	else
		if ! commit_error="$(git -C "${repo_path}" commit --no-gpg-sign -F "${msg_file}" 2>&1)"; then
			error_hint="${commit_error%%$'\n'*}"
			mcp_fail -32603 "Failed to create split commit $((i + 1))/${split_count}: ${error_hint}"
		fi
	fi
	new_hash="$(git -C "${repo_path}" rev-parse HEAD)"
	files_json="${split_files_json}"
	# shellcheck disable=SC2016
	commit_json="$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--arg hash "${new_hash}" \
		--arg message "${message}" \
		--argjson files "${files_json}" \
		'{hash: $hash, message: $message, files: $files}' 2>/dev/null || true)"
	if [ -z "${commit_json}" ]; then
		# Fallback: build commit JSON manually
		hash_esc="$(mcp_json_escape "${new_hash}")"
		msg_esc="$(mcp_json_escape "${message}")"
		commit_json="{\"hash\":${hash_esc},\"message\":${msg_esc},\"files\":${files_json}}"
	fi
	# shellcheck disable=SC2016
	updated_json="$(printf '%s' "${new_commits_json}" | "${MCPBASH_JSON_TOOL_BIN}" --argjson c "${commit_json}" '. + [$c]' 2>/dev/null || true)"
	if [ -n "${updated_json}" ]; then
		new_commits_json="${updated_json}"
	else
		# Fallback: append manually (remove trailing ], add comma if needed, append new, close)
		if [ "${new_commits_json}" = "[]" ]; then
			new_commits_json="[${commit_json}]"
		else
			new_commits_json="${new_commits_json%]},${commit_json}]"
		fi
	fi
done

# Continue rebase
rebase_paused="false"
if ! git -C "${repo_path}" rebase --continue >/dev/null 2>&1; then
	rebase_paused="true"
	_git_hex_abort_rebase="false"
else
	_git_hex_abort_rebase="false"
fi

stash_not_restored="false"
if [ "${auto_stash}" = "true" ]; then
	if [ "${rebase_paused}" = "true" ]; then
		stash_not_restored="true"
	else
		stash_not_restored="$(git_hex_restore_stash "${repo_path}" "${stash_created}")"
	fi
fi

# Record post-operation state for undo safety checks
head_after="$(git -C "${repo_path}" rev-parse HEAD)"
git_hex_record_last_head "${repo_path}" "${head_after}"

trap - EXIT
cleanup

summary="Split ${full_commit:0:7} into ${split_count} commits"

# Validate new_commits_json is valid JSON array before using with jq
if ! printf '%s' "${new_commits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -e '.' >/dev/null 2>&1; then
	printf 'ERROR: new_commits_json is invalid JSON: %s\n' "${new_commits_json:-<empty>}" >&2
	new_commits_json="[]"
fi

# Build output JSON - if jq fails, fall back to manual construction
# shellcheck disable=SC2016
output_json="$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg originalCommit "${full_commit}" \
	--argjson newCommits "${new_commits_json}" \
	--arg backupRef "${backup_ref}" \
	--argjson rebasePaused "${rebase_paused}" \
	--argjson stashNotRestored "${stash_not_restored}" \
	--arg summary "${summary}" \
	'{success: $success, originalCommit: $originalCommit, newCommits: $newCommits, backupRef: $backupRef, rebasePaused: $rebasePaused, stashNotRestored: $stashNotRestored, summary: $summary}' 2>/dev/null || true)"

if [ -z "${output_json}" ]; then
	# jq failed - construct JSON manually
	printf 'WARNING: jq output construction failed, using manual fallback\n' >&2
	original_esc="$(mcp_json_escape "${full_commit}")"
	backup_esc="$(mcp_json_escape "${backup_ref}")"
	summary_esc="$(mcp_json_escape "${summary}")"
	output_json="{\"success\":true,\"originalCommit\":${original_esc},\"newCommits\":${new_commits_json},\"backupRef\":${backup_esc},\"rebasePaused\":${rebase_paused},\"stashNotRestored\":${stash_not_restored},\"summary\":${summary_esc}}"
fi

mcp_emit_json "${output_json}"
