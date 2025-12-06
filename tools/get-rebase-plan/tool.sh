#!/usr/bin/env bash
set -euo pipefail

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
			# Only one commit - use the root commit as onto
			onto="$(git -C "${repo_path}" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)"
		else
			onto="HEAD~${offset}"
		fi
	fi
fi

# Verify onto ref exists
if ! git -C "${repo_path}" rev-parse "${onto}" >/dev/null 2>&1; then
	mcp_fail_invalid_args "Invalid onto ref: ${onto}"
fi

# Generate unique plan ID
plan_id="plan_$(date +%s)_$$"

# Get commits in a single pass using null-byte delimiters for safety
# Format: hash<NUL>shortHash<NUL>subject<NUL>author<NUL>date<NUL> (repeated per commit)
# This is O(1) git forks instead of O(N*5) and handles all special characters safely
commits_json="["
sep=""
commit_count=0

# Use process substitution to read null-delimited fields
# Each commit produces 5 null-terminated fields
while IFS= read -r -d '' hash && \
      IFS= read -r -d '' short_hash && \
      IFS= read -r -d '' subject && \
      IFS= read -r -d '' author && \
      IFS= read -r -d '' date; do
	
	# Skip if we've reached the count limit
	if [ "${commit_count}" -ge "${count}" ]; then
		break
	fi
	
	# Use jq for proper JSON escaping (handles quotes, newlines, tabs, unicode, etc.)
	commit_obj="$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--arg hash "${hash}" \
		--arg shortHash "${short_hash}" \
		--arg subject "${subject}" \
		--arg author "${author}" \
		--arg date "${date}" \
		'{hash: $hash, shortHash: $shortHash, subject: $subject, author: $author, date: $date}')"
	
	commits_json="${commits_json}${sep}${commit_obj}"
	sep=","
	commit_count=$((commit_count + 1))
done < <(git -C "${repo_path}" log --reverse --format='%H%x00%h%x00%s%x00%an%x00%aI%x00' "${onto}..HEAD" 2>/dev/null || true)

commits_json="${commits_json}]"

# Build and emit result using jq for proper escaping
result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--arg plan_id "${plan_id}" \
	--arg branch "${branch}" \
	--arg onto "${onto}" \
	--argjson commits "${commits_json}" \
	'{plan_id: $plan_id, branch: $branch, onto: $onto, commits: $commits}')"
mcp_emit_json "${result}"
