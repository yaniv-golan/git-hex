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
# shellcheck source=../../lib/git-helpers.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/git-helpers.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"

# Validate repo
git_hex_require_repo "${repo_path}"

operation=""
git_dir="$(git_hex_get_git_dir "${repo_path}")"
rebase_msg_dir_marker="${git_dir}/git-hex-rebase-msg-dir"
operation="$(git_hex_get_in_progress_operation_from_git_dir "${git_dir}")"
if [ -z "${operation}" ]; then
	mcp_fail_invalid_args "No rebase/merge/cherry-pick in progress"
fi

status="true"
completed="false"
paused="false"
conflicting_json="[]"
summary=""
error_msg=""

if  [ "${operation}" = "rebase" ]; then
	if rebase_err="$(GIT_EDITOR=true git -c commit.gpgsign=false -C "${repo_path}" rebase --continue 2>&1)"; then
		completed="true"
		summary="Rebase completed successfully"
		_git_hex_cleanup_rebase_msg_dir "${rebase_msg_dir_marker}"
	else
		conflicting_json="[]"
		have_conflicts="false"
		# Use NUL-delimited output to avoid mis-parsing filenames containing newlines.
		while IFS= read -r -d '' conflict_file; do
			[ -z "${conflict_file}" ] && continue
			have_conflicts="true"
			# shellcheck disable=SC2016
			conflicting_json="$(printf '%s' "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${conflict_file}" '. + [$f]')"
		done < <(git -C "${repo_path}" diff --name-only --diff-filter=U -z 2>/dev/null || true)
		if [ "${have_conflicts}" = "true" ]; then
			paused="true"
			summary="Cannot continue - conflicts still present. Resolve remaining conflicts first."
			status="false"
		else
			status="false"
			error_msg="$(echo "${rebase_err}" | head -1)"
			summary="Failed to continue rebase (no conflicts detected). ${error_msg}"
		fi
	fi
elif  [ "${operation}" = "cherry-pick" ]; then
	if cherry_err="$(GIT_EDITOR=true git -c commit.gpgsign=false -C "${repo_path}" cherry-pick --continue 2>&1)"; then
		completed="true"
		summary="Cherry-pick completed successfully"
	else
		conflicting_json="[]"
		have_conflicts="false"
		# Use NUL-delimited output to avoid mis-parsing filenames containing newlines.
		while IFS= read -r -d '' conflict_file; do
			[ -z "${conflict_file}" ] && continue
			have_conflicts="true"
			# shellcheck disable=SC2016
			conflicting_json="$(printf '%s' "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${conflict_file}" '. + [$f]')"
		done < <(git -C "${repo_path}" diff --name-only --diff-filter=U -z 2>/dev/null || true)
		if [ "${have_conflicts}" = "true" ]; then
			paused="true"
			summary="Cannot continue - conflicts still present. Resolve remaining conflicts first."
			status="false"
		else
			status="false"
			error_msg="$(echo "${cherry_err}" | head -1)"
			summary="Failed to continue cherry-pick (no conflicts detected). ${error_msg}"
		fi
	fi
else
	if merge_err="$(GIT_EDITOR=true git -c commit.gpgsign=false -C "${repo_path}" merge --continue 2>&1)"; then
		completed="true"
		summary="Merge completed successfully"
	else
		conflicting_json="[]"
		have_conflicts="false"
		# Use NUL-delimited output to avoid mis-parsing filenames containing newlines.
		while IFS= read -r -d '' conflict_file; do
			[ -z "${conflict_file}" ] && continue
			have_conflicts="true"
			# shellcheck disable=SC2016
			conflicting_json="$(printf '%s' "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${conflict_file}" '. + [$f]')"
		done < <(git -C "${repo_path}" diff --name-only --diff-filter=U -z 2>/dev/null || true)
		if [ "${have_conflicts}" = "true" ]; then
			paused="true"
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
	'{success: $success, operationType: $operationType, completed: $completed, paused: $paused, conflictingFiles: $conflictingFiles, summary: $summary}
	| if ($error | length) > 0 then . + {error: $error} else . end')"
