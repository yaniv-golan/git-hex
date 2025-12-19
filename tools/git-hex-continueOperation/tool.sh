#!/usr/bin/env bash
set -euo pipefail

# Enable shell tracing for debugging (shows every command executed)
if [ "${GIT_HEX_DEBUG:-}" = "true" ]; then
	set -x
fi

# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/rebase-msg-dir.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/rebase-msg-dir.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"

# Validate repo
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

operation=""
git_dir="$(git -C "${repo_path}" rev-parse --git-dir 2>/dev/null || true)"
case "${git_dir}" in
/*) ;;
*) git_dir="${repo_path}/${git_dir}" ;;
esac
rebase_merge_dir="${git_dir}/rebase-merge"
rebase_apply_dir="${git_dir}/rebase-apply"
cherry_pick_head_path="${git_dir}/CHERRY_PICK_HEAD"
merge_head_path="${git_dir}/MERGE_HEAD"
rebase_msg_dir_marker="${git_dir}/git-hex-rebase-msg-dir"
if { [ -n "${rebase_merge_dir}" ] && [ -d "${rebase_merge_dir}" ]; } || { [ -n "${rebase_apply_dir}" ] && [ -d "${rebase_apply_dir}" ]; }; then
	operation="rebase"
elif [ -n "${cherry_pick_head_path}" ] && [ -f "${cherry_pick_head_path}" ]; then
	operation="cherry-pick"
elif [ -n "${merge_head_path}" ] && [ -f "${merge_head_path}" ]; then
	operation="merge"
else
	mcp_fail_invalid_args "No rebase/merge/cherry-pick in progress"
fi

status="true"
completed="false"
paused="false"
conflicting_json="[]"
summary=""
error_msg=""

if [ "${operation}" = "rebase" ]; then
	if rebase_err="$(GIT_EDITOR=true git -C "${repo_path}" rebase --continue 2>&1)"; then
		completed="true"
		summary="Rebase completed successfully"
		_git_hex_cleanup_rebase_msg_dir "${rebase_msg_dir_marker}"
	else
		conflicts="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"
		if [ -n "${conflicts}" ]; then
			paused="true"
			while IFS= read -r cf; do
				[ -z "${cf}" ] && continue
				# shellcheck disable=SC2016
				conflicting_json="$(printf '%s' "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
			done <<<"${conflicts}"
			summary="Cannot continue - conflicts still present. Resolve remaining conflicts first."
			status="false"
		else
			status="false"
			error_msg="$(echo "${rebase_err}" | head -1)"
			summary="Failed to continue rebase (no conflicts detected). ${error_msg}"
		fi
	fi
elif [ "${operation}" = "cherry-pick" ]; then
	if cherry_err="$(GIT_EDITOR=true git -C "${repo_path}" cherry-pick --continue 2>&1)"; then
		completed="true"
		summary="Cherry-pick completed successfully"
	else
		conflicts="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"
		if [ -n "${conflicts}" ]; then
			paused="true"
			while IFS= read -r cf; do
				[ -z "${cf}" ] && continue
				# shellcheck disable=SC2016
				conflicting_json="$(printf '%s' "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
			done <<<"${conflicts}"
			summary="Cannot continue - conflicts still present. Resolve remaining conflicts first."
			status="false"
		else
			status="false"
			error_msg="$(echo "${cherry_err}" | head -1)"
			summary="Failed to continue cherry-pick (no conflicts detected). ${error_msg}"
		fi
	fi
else
	if merge_err="$(GIT_EDITOR=true git -C "${repo_path}" merge --continue 2>&1)"; then
		completed="true"
		summary="Merge completed successfully"
	else
		conflicts="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"
		if [ -n "${conflicts}" ]; then
			paused="true"
			while IFS= read -r cf; do
				[ -z "${cf}" ] && continue
				# shellcheck disable=SC2016
				conflicting_json="$(printf '%s' "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
			done <<<"${conflicts}"
			summary="Cannot continue - conflicts still present. Resolve remaining conflicts first."
			status="false"
		else
			status="false"
			error_msg="$(echo "${merge_err}" | head -1)"
			summary="Failed to continue merge (no conflicts detected). ${error_msg}"
		fi
	fi
fi

# shellcheck disable=SC2016
mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success "${status}" \
	--arg operationType "${operation}" \
	--argjson completed "${completed}" \
	--argjson paused "${paused}" \
	--argjson conflictingFiles "${conflicting_json}" \
	--arg error "${error_msg}" \
	--arg summary "${summary}" \
	'{success: $success, operationType: $operationType, completed: $completed, paused: $paused, conflictingFiles: $conflictingFiles, error: $error, summary: $summary}')"
