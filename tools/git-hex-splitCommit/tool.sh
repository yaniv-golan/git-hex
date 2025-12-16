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
trimmed_splits="$(echo "${splits_json:-}" | tr -d '[:space:]')"
if [ -z "${trimmed_splits}" ] || [ "${trimmed_splits}" = "null" ]; then
	splits_json="[]"
else
	splits_json="${splits_json:-}"
fi
auto_stash="$(mcp_args_bool '.autoStash' --default false)"

if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

git_dir="$(git -C "${repo_path}" rev-parse --git-dir 2>/dev/null || true)"
case "${git_dir}" in
/*) ;;
*) git_dir="${repo_path}/${git_dir}" ;;
esac
rebase_merge_dir="${git_dir}/rebase-merge"
rebase_apply_dir="${git_dir}/rebase-apply"
if { [ -n "${rebase_merge_dir}" ] && [ -d "${rebase_merge_dir}" ]; } || { [ -n "${rebase_apply_dir}" ] && [ -d "${rebase_apply_dir}" ]; }; then
	mcp_fail_invalid_args "Cannot split commit while rebase is in progress"
fi

# Resolve commit
full_commit="$(git -C "${repo_path}" rev-parse --verify "${commit_ref}^{commit}" 2>/dev/null || true)"
if [ -z "${full_commit}" ]; then
	mcp_fail_invalid_args "Invalid commit: ${commit_ref}"
fi

# Commit must not be merge commit
if [ "$(git -C "${repo_path}" rev-list --count "${full_commit}^@" 2>/dev/null)" -gt 1 ]; then
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

original_files="$(git -C "${repo_path}" diff-tree --no-commit-id --name-only -r "${full_commit}")"
if [ -z "${original_files}" ]; then
	mcp_fail_invalid_args "Commit ${commit_ref} has no file changes"
fi

# Validate coverage
covered_files=""
for i in $(seq 0 $((split_count - 1))); do
	split_files="$(printf '%s' "${splits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i].files[]?" 2>/dev/null || true)"
	message="$(printf '%s' "${splits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i].message" 2>/dev/null || true)"
	if [ -z "${split_files}" ]; then
		mcp_fail_invalid_args "Split $((i + 1)) has no files"
	fi
	if printf '%s' "${message}" | grep -q $'[\t\n]'; then
		mcp_fail_invalid_args "Split message cannot contain TAB or newline"
	fi
	while IFS= read -r file; do
		[ -z "${file}" ] && continue
		if ! echo "${original_files}" | grep -qx "${file}"; then
			mcp_fail_invalid_args "File '${file}' not in original commit"
		fi
		if echo "${covered_files}" | grep -qx "${file}"; then
			mcp_fail_invalid_args "File '${file}' appears in multiple splits"
		fi
		covered_files="${covered_files}${file}"$'\n'
	done <<<"${split_files}"
done

while IFS= read -r file; do
	[ -z "${file}" ] && continue
	if ! echo "${covered_files}" | grep -qx "${file}"; then
		mcp_fail_invalid_args "File '${file}' from original commit not assigned to any split"
	fi
done <<<"${original_files}"

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

cat >"${seq_editor}"  <<'EDITOR_SCRIPT'
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
rebase_output="$(GIT_SEQUENCE_EDITOR="${seq_editor}" git -C "${repo_path}" rebase -i "${commit_parent}" 2>&1)" || rebase_status=$?

unset GIT_HEX_TARGET_FULL GIT_HEX_TARGET_SUBJECT GIT_HEX_REPO_PATH

if { [ -z "${rebase_merge_dir}" ] || [ ! -d "${rebase_merge_dir}" ]; } && { [ -z "${rebase_apply_dir}" ] || [ ! -d "${rebase_apply_dir}" ]; }; then
	# Rebase did not pause as expected
	if [ "${auto_stash}" = "true" ]; then
		git_hex_restore_stash "${repo_path}" "${stash_created}" >/dev/null
	fi
	error_hint="$(echo "${rebase_output}" | head -1)"
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
for i in $(seq 0 $((split_count - 1))); do
	split_files="$(printf '%s' "${splits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i].files[]?" 2>/dev/null || true)"
	message="$(printf '%s' "${splits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r ".[$i].message" 2>/dev/null || true)"
	msg_file="${msg_dir}/msg_${i}.txt"
	printf '%s\n' "${message}" >"${msg_file}"
	while IFS= read -r file; do
		[ -z "${file}" ] && continue
		git -C "${repo_path}" add -- "${file}"
	done <<<"${split_files}"
	git -C "${repo_path}" commit -F "${msg_file}" >/dev/null 2>&1
	new_hash="$(git -C "${repo_path}" rev-parse HEAD)"
	files_json="$(printf '%s' "${split_files}" | "${MCPBASH_JSON_TOOL_BIN}" -R -s 'split("\n") | map(select(length>0))')"
	# shellcheck disable=SC2016
	commit_json="$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--arg hash "${new_hash}" \
		--arg message "${message}" \
		--argjson files "${files_json}" \
		'{hash: $hash, message: $message, files: $files}')"
	# shellcheck disable=SC2016
	new_commits_json="$(printf '%s' "${new_commits_json}" | "${MCPBASH_JSON_TOOL_BIN}" --argjson c "${commit_json}" '. + [$c]')"
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

# shellcheck disable=SC2016
output_json="$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg originalCommit "${full_commit}" \
	--argjson newCommits "${new_commits_json}" \
	--arg backupRef "${backup_ref}" \
	--argjson rebasePaused "${rebase_paused}" \
	--argjson stashNotRestored "${stash_not_restored}" \
	--arg summary "Split ${full_commit:0:7} into ${split_count} commits" \
	'{success: $success, originalCommit: $originalCommit, newCommits: $newCommits, backupRef: $backupRef, rebasePaused: $rebasePaused, stashNotRestored: $stashNotRestored, summary: $summary}')"

if [ "${GIT_HEX_DEBUG_SPLIT:-}" = "true" ]; then
	printf '%s\n' "${output_json}" >&2
	printf '%s\n' "${output_json}" >"${TMPDIR:-/tmp}/git-hex-split-debug.json"
fi

mcp_emit_json "${output_json}"
