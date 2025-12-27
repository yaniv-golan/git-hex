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

git_hex_require_repo "${repo_path}"
mcp_log_info "git-hex" "Checking for operation to abort"

operation=""
git_dir="$(git_hex_get_git_dir "${repo_path}")"
rebase_msg_dir_marker="${git_dir}/git-hex-rebase-msg-dir"
operation="$(git_hex_get_in_progress_operation_from_git_dir "${git_dir}")"

if  [ -z "${operation}" ]; then
	# No operation in progress - return success: false in result data to indicate semantic failure
	result='{"operationSucceeded": false, "operationType": "none", "error": "No rebase/merge/cherry-pick in progress", "summary": "Nothing to abort"}'
	mcp_result_success "${result}"
	exit 0
fi

mcp_log_info "git-hex" "Aborting ${operation} operation"
if  [ "${operation}" = "rebase" ]; then
	git -C "${repo_path}" rebase --abort >/dev/null 2>&1 || true
	_git_hex_cleanup_rebase_msg_dir "${rebase_msg_dir_marker}"
elif  [ "${operation}" = "cherry-pick" ]; then
	git -C "${repo_path}" cherry-pick --abort >/dev/null 2>&1 || true
elif  [ "${operation}" = "merge" ]; then
	git -C "${repo_path}" merge --abort >/dev/null 2>&1 || true
else
	# Unsupported operation - return operationSucceeded: false in result data
	# shellcheck disable=SC2016
	result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--argjson operationSucceeded false \
		--arg operationType "${operation}" \
		--arg error "Abort is only supported for rebase, cherry-pick, or merge" \
		--arg summary "Nothing aborted" \
		'{operationSucceeded: $operationSucceeded, operationType: $operationType, error: $error, summary: $summary}')"
	mcp_result_success "${result}"
	exit 0
fi

summary="${operation} aborted, restored to original state"
# Build and emit result (mcp_result_success wraps in {success: true, result: ...} envelope)
# shellcheck disable=SC2016
result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--arg operationType "${operation}" \
	--arg summary "${summary}" \
	'{operationType: $operationType, summary: $summary}')"
mcp_result_success "${result}"
