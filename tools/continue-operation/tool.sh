#!/usr/bin/env bash
set -euo pipefail

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

if [ "${operation}" = "rebase" ]; then
	if GIT_EDITOR=true git -C "${repo_path}" rebase --continue >/dev/null 2>&1; then
		completed="true"
		summary="Rebase completed successfully"
	else
		paused="true"
		conflicts="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"
		while IFS= read -r cf; do
			[ -z "${cf}" ] && continue
			conflicting_json="$(echo "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
		done <<<"${conflicts}"
		summary="Cannot continue - conflicts still present. Resolve remaining conflicts first."
		status="false"
	fi
elif [ "${operation}" = "cherry-pick" ]; then
	if GIT_EDITOR=true git -C "${repo_path}" cherry-pick --continue >/dev/null 2>&1; then
		completed="true"
		summary="Cherry-pick completed successfully"
	else
		paused="true"
		conflicts="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"
		while IFS= read -r cf; do
			[ -z "${cf}" ] && continue
			conflicting_json="$(echo "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
		done <<<"${conflicts}"
		summary="Cannot continue - conflicts still present. Resolve remaining conflicts first."
		status="false"
	fi
else
	if GIT_EDITOR=true git -C "${repo_path}" merge --continue >/dev/null 2>&1; then
		completed="true"
		summary="Merge completed successfully"
	else
		paused="true"
		conflicts="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"
		while IFS= read -r cf; do
			[ -z "${cf}" ] && continue
			conflicting_json="$(echo "${conflicting_json}" | "${MCPBASH_JSON_TOOL_BIN}" --arg f "${cf}" '. + [$f]')"
		done <<<"${conflicts}"
		summary="Cannot continue - conflicts still present. Resolve remaining conflicts first."
		status="false"
	fi
fi

mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success "${status}" \
	--arg operationType "${operation}" \
	--argjson completed "${completed}" \
	--argjson paused "${paused}" \
	--argjson conflictingFiles "${conflicting_json}" \
	--arg summary "${summary}" \
	'{success: $success, operationType: $operationType, completed: $completed, paused: $paused, conflictingFiles: $conflictingFiles, summary: $summary}')"
