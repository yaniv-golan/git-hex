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

# Get commit hashes (oldest first for rebase order)
# We query each commit separately to avoid delimiter issues with special characters
# in commit messages (pipes, tabs, quotes, newlines, etc.)
commit_hashes="$(git -C "${repo_path}" log --reverse --format='%H' "${onto}..HEAD" 2>/dev/null | head -n "${count}" || true)"

# Build JSON array of commits using jq for proper escaping
commits_json="["
sep=""
while IFS= read -r hash; do
	[ -z "${hash}" ] && continue
	
	# Query each field separately - slower but 100% reliable
	short_hash="$(git -C "${repo_path}" rev-parse --short "${hash}")"
	subject="$(git -C "${repo_path}" log -1 --format='%s' "${hash}")"
	author="$(git -C "${repo_path}" log -1 --format='%an' "${hash}")"
	date="$(git -C "${repo_path}" log -1 --format='%aI' "${hash}")"
	
	# Use jq for proper JSON escaping of all fields (handles quotes, newlines, tabs, etc.)
	commit_obj="$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--arg hash "${hash}" \
		--arg shortHash "${short_hash}" \
		--arg subject "${subject}" \
		--arg author "${author}" \
		--arg date "${date}" \
		'{hash: $hash, shortHash: $shortHash, subject: $subject, author: $author, date: $date}')"
	
	commits_json="${commits_json}${sep}${commit_obj}"
	sep=","
done <<<"${commit_hashes}"
commits_json="${commits_json}]"

# Build and emit result using jq for proper escaping
result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--arg plan_id "${plan_id}" \
	--arg branch "${branch}" \
	--arg onto "${onto}" \
	--argjson commits "${commits_json}" \
	'{plan_id: $plan_id, branch: $branch, onto: $onto, commits: $commits}')"
mcp_emit_json "${result}"
