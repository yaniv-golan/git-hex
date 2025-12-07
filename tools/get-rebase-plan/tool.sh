#!/usr/bin/env bash
set -euo pipefail

# Enable shell tracing for debugging (shows every command executed)
if [ "${GIT_HEX_DEBUG:-}" = "true" ]; then
	set -x
fi

# Source SDK (MCP_SDK is set by the framework when running tools)
# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
count="$(mcp_args_int '.count' --default 10 --min 1 --max 200)"
onto="$(mcp_args_get '.onto // empty' || true)"

# Validate git repository
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

# Get current branch
branch="$(git -C "${repo_path}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -z "${branch}" ] || [ "${branch}" = "HEAD" ]; then
	branch="(detached HEAD)"
fi

# Determine base ref for rebase
if [ -z "${onto}" ]; then
	# Default to upstream tracking branch or HEAD~count (clamped to repo size)
	onto="$(git -C "${repo_path}" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
	if [ -z "${onto}" ]; then
		# Get total commit count and clamp to avoid HEAD~N where N > total commits
		total_commits="$(git -C "${repo_path}" rev-list --count HEAD 2>/dev/null || echo "0")"
		if [ "${total_commits}" -eq 0 ]; then
			mcp_fail_invalid_args "Repository has no commits"
		fi
		# Use the smaller of count or (total_commits - 1) to ensure valid ref
		# We need at least 1 commit as base, so max offset is total_commits - 1
		max_offset=$((total_commits - 1))
		if [ "${count}" -gt "${max_offset}" ]; then
			offset="${max_offset}"
		else
			offset="${count}"
		fi
		if [ "${offset}" -eq 0 ]; then
			# Only one commit - use empty tree as base to include it
			# This allows single-commit repos to show their only commit
			onto="4b825dc642cb6eb9a060e54bf8d69288fbee4904" # git's empty tree SHA
		else
			onto="HEAD~${offset}"
		fi
	fi
fi

# Verify onto ref exists (except for empty tree which always exists)
if [ "${onto}" != "4b825dc642cb6eb9a060e54bf8d69288fbee4904" ]; then
	if ! git -C "${repo_path}" rev-parse "${onto}" >/dev/null 2>&1; then
		mcp_fail_invalid_args "Invalid onto ref: ${onto}"
	fi
fi

# Generate unique plan ID
plan_id="plan_$(date +%s)_$$"

# Get commits using null-byte delimiters for safety (handles all special chars)
# Using -z flag to use NUL as record terminator, and %x00 between fields
# Pipe directly to jq to avoid bash null-byte warning in command substitution
# This is O(1) git and jq invocations regardless of commit count
# shellcheck disable=SC2016
commits_json="$(git -C "${repo_path}" log --reverse -n "${count}" -z \
	--format='%H%x00%h%x00%s%x00%an%x00%aI' \
	"${onto}..HEAD" 2>/dev/null | "${MCPBASH_JSON_TOOL_BIN}" -Rs '
	split("\u0000") |
	# Group into chunks of 5 fields per commit
	[range(0; length; 5) as $i | .[$i:$i+5]] |
	# Filter complete records (must have exactly 5 fields)
	map(select(length == 5)) |
	map({
		hash: .[0],
		shortHash: .[1],
		subject: .[2],
		author: .[3],
		date: .[4]
	})
' || echo "[]")"

# Handle empty result
if [ -z "${commits_json}" ] || [ "${commits_json}" = "null" ]; then
	commits_json="[]"
fi

# Resolve onto to display value (show original ref, not empty tree hash)
onto_display="${onto}"
if [ "${onto}" = "4b825dc642cb6eb9a060e54bf8d69288fbee4904" ]; then
	onto_display="(root)"
fi

# Count commits for summary
commit_count="$(echo "${commits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r 'length')"

# Build and emit result
# shellcheck disable=SC2016
result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg plan_id "${plan_id}" \
	--arg branch "${branch}" \
	--arg onto "${onto_display}" \
	--argjson commits "${commits_json}" \
	--arg summary "Found ${commit_count} commits on ${branch} since ${onto_display}" \
	'{success: $success, plan_id: $plan_id, branch: $branch, onto: $onto, commits: $commits, summary: $summary}')"
mcp_emit_json "${result}"
