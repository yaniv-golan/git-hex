#!/usr/bin/env bash
set -euo pipefail

# Enable shell tracing for debugging (shows every command executed)
if [ "${GIT_HEX_DEBUG:-}" = "true" ]; then
	set -x
fi

# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/git-helpers.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/git-helpers.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
file="$(mcp_args_require '.file')"
resolution="$(mcp_args_get '.resolution' || true)"
: "${resolution:=keep}"

# Basic path safety checks
git_hex_require_safe_repo_relative_path "${file}"

# Validate repo
git_hex_require_repo "${repo_path}"

# Directory guard
if [ -d "${repo_path}/${file}" ]; then
	mcp_fail_invalid_args "Path '${file}' is a directory, not a file"
fi

# Determine conflict status for the file
unmerged="$(git -C "${repo_path}" ls-files -u -- "${file}" 2>/dev/null || true)"

if [ -z "${unmerged}" ] && [ ! -f "${repo_path}/${file}" ]; then
	mcp_fail_invalid_args "File not found and not in conflict state: ${file}"
fi

if [ -f "${repo_path}/${file}" ]; then
	if [ -z "${unmerged}" ]; then
		mcp_fail_invalid_args "File not in conflict state: ${file}"
	fi
	if [ "${resolution}" = "delete" ]; then
		git -C "${repo_path}" rm -f -- "${file}" >/dev/null 2>&1
	else
		if grep -q "^<<<<<<< " "${repo_path}/${file}" 2>/dev/null; then
			mcp_fail_invalid_args "File still contains conflict markers. Please resolve all conflicts first."
		fi
		git -C "${repo_path}" add -- "${file}"
	fi
elif [ -n "${unmerged}" ]; then
	stages="$(printf '%s\n' "${unmerged}" | awk '{print $3}' | sort -u | tr '\n' ',')"
	if [ "${resolution}" = "delete" ]; then
		git -C "${repo_path}" rm -f --cached -- "${file}" >/dev/null 2>&1
	else
		case "${stages}" in
		"1,3,")
			# deleted_by_us: restore theirs
			if ! git -C "${repo_path}" checkout --theirs -- "${file}" >/dev/null 2>&1; then
				mcp_fail -32603 "Failed to restore '${file}' from theirs - manual resolution required"
			fi
			if ! git -C "${repo_path}" add -- "${file}" >/dev/null 2>&1; then
				mcp_fail -32603 "Failed to stage '${file}' after restore - manual resolution required"
			fi
			;;
		"1,2,")
			# deleted_by_them: restore ours
			if ! git -C "${repo_path}" checkout --ours -- "${file}" >/dev/null 2>&1; then
				mcp_fail -32603 "Failed to restore '${file}' from ours - manual resolution required"
			fi
			if ! git -C "${repo_path}" add -- "${file}" >/dev/null 2>&1; then
				mcp_fail -32603 "Failed to stage '${file}' after restore - manual resolution required"
			fi
			;;
		*)
			mcp_fail_invalid_args "Cannot keep file '${file}' - restore it manually or use resolution='delete'."
			;;
		esac
	fi
else
	mcp_fail_invalid_args "File not found and not in conflict state: ${file}"
fi

remaining="0"
while  IFS= read -r -d '' _conflict_file; do
	remaining="$((remaining + 1))"
done  < <(git -C "${repo_path}" diff --name-only --diff-filter=U -z 2>/dev/null || true)

# shellcheck disable=SC2016
mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg file "${file}" \
	--argjson remainingConflicts "${remaining}" \
	--arg summary "Marked ${file} as resolved. ${remaining} conflict(s) remaining." \
	'{success: $success, file: $file, remainingConflicts: $remainingConflicts, summary: $summary}')"
