#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"

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
fi

if [ -z "${operation}" ]; then
	mcp_emit_json '{"success": false, "error": "No rebase/merge/cherry-pick in progress", "summary": "Nothing to abort"}'
	exit 0
fi

if [ "${operation}" = "rebase" ]; then
	git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
elif [ "${operation}" = "cherry-pick" ]; then
	git -C "${repo_path}" cherry-pick --abort >/dev/null 2>&1 || true
else
	git -C "${repo_path}" merge --abort >/dev/null 2>&1 || true
fi

summary="${operation} aborted, restored to original state"
# shellcheck disable=SC2016
mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg operationType "${operation}" \
	--arg summary "${summary}" \
	'{success: $success, operationType: $operationType, summary: $summary}')"
