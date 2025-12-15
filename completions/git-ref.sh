#!/usr/bin/env bash
set -euo pipefail

# Completion provider: git ref suggestions (branches/tags).
#
# Inputs:
# - MCP_COMPLETION_ARGS_JSON: normalized args (provided by MCP Bash Framework)
# - MCP_COMPLETION_LIMIT / MCP_COMPLETION_OFFSET
#
# Expected args (best-effort):
# - .context.arguments.repoPath (optional): absolute path to target git repository
# - .query or .prefix (optional): partial input

if [ -z "${MCPBASH_JSON_TOOL_BIN:-}" ] || ! command -v "${MCPBASH_JSON_TOOL_BIN}" >/dev/null 2>&1; then
	printf '{"suggestions":[],"hasMore":false,"next":null}'
	exit 0
fi

json_bin="${MCPBASH_JSON_TOOL_BIN}"

args_json="${MCP_COMPLETION_ARGS_JSON:-{}}"
limit="${MCP_COMPLETION_LIMIT:-20}"
offset="${MCP_COMPLETION_OFFSET:-0}"

repo_path="$(printf '%s' "${args_json}" | "${json_bin}" -r '(.context.arguments.repoPath // .repoPath // "")' 2>/dev/null || printf '')"
query="$(printf '%s' "${args_json}" | "${json_bin}" -r '(.query // .prefix // .argument.value // "")' 2>/dev/null || printf '')"

if [ -z "${repo_path}" ] || [ ! -d "${repo_path}" ]; then
	printf '%s' "$(${json_bin} -n -c '{suggestions: [], hasMore: false, next: null}')"
	exit 0
fi

refs_raw="$(git -C "${repo_path}" for-each-ref --format='%(refname:short)' refs/heads refs/tags 2>/dev/null || true)"

filtered=""
if [ -n "${query}" ]; then
	while IFS= read -r line; do
		[ -n "${line}" ] || continue
		case "${line}" in
		"${query}"*) filtered="${filtered}${line}
" ;;
		esac
	done <<<"${refs_raw}"
else
	filtered="${refs_raw}"
fi

# shellcheck disable=SC2016
printf '%s' "${filtered}" | "${json_bin}" -R -s -c --argjson limit "${limit}" --argjson offset "${offset}" '
	split("\n")
	| map(select(length > 0))
	| . as $all
	| ($all[$offset:$offset+$limit]) as $page
	| ($page | length) as $count
	| ($all | length) as $total
	| {
		suggestions: $page,
		hasMore: (($offset + $count) < $total),
		next: (if (($offset + $count) < $total) then ($offset + $count) else null end)
	}
'
