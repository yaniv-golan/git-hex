#!/usr/bin/env bash
set -euo pipefail

# Enable shell tracing for debugging (shows every command executed)
if [ "${GIT_HEX_DEBUG:-}" = "true" ]; then
	set -x
fi

# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"

# Validate repo
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

operation=""
if [ -d "${repo_path}/.git/rebase-merge" ] || [ -d "${repo_path}/.git/rebase-apply" ]; then
	operation="rebase"
elif [ -f "${repo_path}/.git/CHERRY_PICK_HEAD" ]; then
	operation="cherry-pick"
elif [ -f "${repo_path}/.git/MERGE_HEAD" ]; then
	operation="merge"
else
	mcp_emit_json '{"success": false, "error": "No rebase/merge/cherry-pick in progress", "summary": "Nothing to continue"}'
	exit 0
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
	else
		conflicts="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"
		if [ -n "${conflicts}" ]; then
			paused="true"
			while IFS= read -r cf; do
				[ -z "${cf}" ] && continue
				# shellcheck disable=SC2016
				conflicting_json="$(echo "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
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
				conflicting_json="$(echo "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
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
				conflicting_json="$(echo "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
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
