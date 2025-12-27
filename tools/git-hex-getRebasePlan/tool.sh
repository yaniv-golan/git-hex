#!/usr/bin/env bash
set -euo pipefail

# Enable shell tracing for debugging (shows every command executed)
if [ "${GIT_HEX_DEBUG:-}" = "true" ]; then
	set -x
fi

# Source SDK (MCP_SDK is set by the framework when running tools)
# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/git-helpers.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/git-helpers.sh"

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
count="$(mcp_args_int '.count' --default 10 --min 1 --max 200)"
onto="$(mcp_args_get '.onto // empty' || true)"

# Validate git repository
git_hex_require_repo "${repo_path}"

# Compute git's empty tree hash (used when treating a single-commit repo as having a root base).
empty_tree_sha="$(git -C "${repo_path}" hash-object -t tree /dev/null 2>/dev/null || true)"
if [ -z "${empty_tree_sha}" ]; then
	mcp_fail -32603 "Failed to compute empty tree hash"
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
			onto="${empty_tree_sha}"
		else
			onto="HEAD~${offset}"
		fi
	fi
fi

# Verify onto ref exists (except for empty tree which always exists)
if  [ "${onto}" != "${empty_tree_sha}" ]; then
	if ! git -C "${repo_path}" rev-parse --verify "${onto}^{commit}" >/dev/null 2>&1; then
		if git_hex_is_shallow_repo "${repo_path}"; then
			mcp_fail_invalid_args "Invalid onto ref: ${onto} (repository is shallow; try git fetch --unshallow)"
		fi
		mcp_fail_invalid_args "Invalid onto ref: ${onto}"
	fi
fi

# Generate unique plan ID
plan_id="plan_$(date +%s)_$$"

commits_json="[]"
log_format='%H%x00%h%x00%s%x00%an%x00%aI'
while IFS= read -r -d '' hash \
	&& IFS= read -r -d '' short_hash \
	&& IFS= read -r -d '' subject \
	&& IFS= read -r -d '' author \
	&& IFS= read -r -d '' date; do
	[ -z "${hash}" ] && continue
	# shellcheck disable=SC2016
	commit_json="$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--arg hash "${hash}" \
		--arg shortHash "${short_hash}" \
		--arg subject "${subject}" \
		--arg author "${author}" \
		--arg date "${date}" \
		'{hash: $hash, shortHash: $shortHash, subject: $subject, author: $author, date: $date}')"
	# shellcheck disable=SC2016
	commits_json="$(printf '%s' "${commits_json}" | "${MCPBASH_JSON_TOOL_BIN}" --argjson c "${commit_json}" '. + [$c]')"
done < <(git -C "${repo_path}" log --reverse -n "${count}" -z --format="${log_format}" "${onto}..HEAD" 2>/dev/null || true)

# Resolve onto to display value (show original ref, not empty tree hash)
onto_display="${onto}"
if [ "${onto}" = "${empty_tree_sha}" ]; then
	onto_display="(root)"
fi

# Count commits for summary
commit_count="$(printf '%s' "${commits_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r 'length')"

summary="Found ${commit_count} commits on ${branch} since ${onto_display}"
if [ "${branch}" = "(detached HEAD)" ]; then
	summary="${summary}. Warning: detached HEAD; rebasing may rewrite commits without an easy branch reference."
fi

# Build and emit result
# shellcheck disable=SC2016
result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg plan_id "${plan_id}" \
	--arg branch "${branch}" \
	--arg onto "${onto_display}" \
	--argjson commits "${commits_json}" \
	--arg summary "${summary}" \
	'{success: $success, plan_id: $plan_id, branch: $branch, onto: $onto, commits: $commits, summary: $summary}')"
mcp_emit_json "${result}"
