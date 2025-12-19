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
fi

if [ -z "${operation}" ]; then
	mcp_emit_json '{"success": false, "error": "No rebase/merge/cherry-pick in progress", "summary": "Nothing to abort"}'
	exit 0
fi

if [ "${operation}" = "rebase" ]; then
	git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
	_git_hex_cleanup_rebase_msg_dir "${rebase_msg_dir_marker}"
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
