#!/usr/bin/env bash
set -euo pipefail

# Source SDK (MCP_SDK is set by the framework when running tools)
# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

# Cleanup function to abort cherry-pick on failure
cleanup() {
	if [ -n "${repo_path:-}" ]; then
		if [ -f "${repo_path}/.git/CHERRY_PICK_HEAD" ]; then
			git -C "${repo_path}" cherry-pick --abort >/dev/null 2>&1 || true
		fi
	fi
}
trap cleanup EXIT

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
commit="$(mcp_args_require '.commit')"
strategy="$(mcp_args_get '.strategy // empty' || true)"
no_commit="$(mcp_args_bool '.noCommit' --default false)"

# Validate strategy if provided (must match schema enum)
if [ -n "${strategy}" ]; then
	case "${strategy}" in
		recursive|ort|resolve|octopus)
			# Valid strategy
			;;
		*)
			mcp_fail_invalid_args "Invalid merge strategy '${strategy}'. Must be one of: recursive, ort, resolve, octopus"
			;;
	esac
fi

# Validate git repository
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

# Check if repository has any commits
if ! git -C "${repo_path}" rev-parse HEAD >/dev/null 2>&1; then
	mcp_fail_invalid_args "Repository has no commits. Nothing to cherry-pick onto."
fi

# Check for uncommitted changes
if ! git -C "${repo_path}" diff-index --quiet HEAD -- 2>/dev/null; then
	mcp_fail_invalid_args "Repository has uncommitted changes. Please commit or stash them first."
fi

# Check if already in cherry-pick state
if [ -f "${repo_path}/.git/CHERRY_PICK_HEAD" ]; then
	mcp_fail_invalid_args "Repository is already in a cherry-pick state. Please resolve or abort it first."
fi

# Verify commit exists and resolve to full hash
source_hash="$(git -C "${repo_path}" rev-parse "${commit}" 2>/dev/null || true)"
if [ -z "${source_hash}" ]; then
	mcp_fail_invalid_args "Invalid commit ref: ${commit}"
fi

# Build cherry-pick command
pick_args=()
if [ -n "${strategy}" ]; then
	pick_args+=("--strategy=${strategy}")
fi
if [ "${no_commit}" = "true" ]; then
	pick_args+=("--no-commit")
fi
pick_args+=("${source_hash}")

# Perform cherry-pick
if git -C "${repo_path}" cherry-pick "${pick_args[@]}" >&2; then
	# Success - clear the trap
	trap - EXIT
	
	if [ "${no_commit}" = "true" ]; then
		mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--argjson success true \
			--arg sourceCommit "${source_hash}" \
			--arg message "Changes from ${source_hash} applied but not committed" \
			'{success: $success, sourceCommit: $sourceCommit, message: $message}')"
	else
		new_hash="$(git -C "${repo_path}" rev-parse HEAD)"
		mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--argjson success true \
			--arg newHash "${new_hash}" \
			--arg sourceCommit "${source_hash}" \
			--arg message "Successfully cherry-picked ${source_hash}" \
			'{success: $success, newHash: $newHash, sourceCommit: $sourceCommit, message: $message}')"
	fi
else
	# Cherry-pick failed - cleanup will abort
	mcp_fail -32603 "Cherry-pick failed due to conflicts. Repository has been restored to original state."
fi
