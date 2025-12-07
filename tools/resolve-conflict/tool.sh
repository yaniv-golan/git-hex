#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
file="$(mcp_args_require '.file')"
resolution="$(mcp_args_get '.resolution' || true)"
: "${resolution:=keep}"

# Basic path safety checks
orig_len="$(printf '%s' "${file}" | LC_ALL=C wc -c | tr -d ' ')"
clean_len="$(printf '%s' "${file}" | LC_ALL=C tr -d '\0' | wc -c | tr -d ' ')"
if [ "${orig_len}" -ne "${clean_len}" ]; then
	mcp_fail_invalid_args "Null bytes are not allowed in paths"
fi
if [[ "${file}" == /* ]]; then
	mcp_fail_invalid_args "Absolute paths are not allowed"
fi
if [[ "${file}" == "../"* || "${file}" == ".." || "${file}" == *"/.."* || "${file}" == *"/../"* ]]; then
	mcp_fail_invalid_args "Path traversal is not allowed"
fi
# Reject Windows-style drive letter paths to avoid ambiguity
case "${file}" in
[A-Za-z]:/* | [A-Za-z]:\\*)
	mcp_fail_invalid_args "Drive-letter paths are not allowed; use repo-relative POSIX paths"
	;;
esac

# Validate repo
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

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
	stages="$(echo "${unmerged}" | awk '{print $3}' | sort -u | tr '\n' ',')"
	if [ "${resolution}" = "delete" ]; then
		git -C "${repo_path}" rm -f --cached -- "${file}" >/dev/null 2>&1
	else
		case "${stages}" in
		"1,3," | "1,3,2,")
			# deleted_by_us: restore theirs
			git -C "${repo_path}" checkout --theirs -- "${file}" >/dev/null 2>&1 || true
			git -C "${repo_path}" add -- "${file}"
			;;
		"1,2," | "1,2,3,")
			# deleted_by_them: restore ours
			git -C "${repo_path}" checkout --ours -- "${file}" >/dev/null 2>&1 || true
			git -C "${repo_path}" add -- "${file}"
			;;
		*)
			mcp_fail_invalid_args "Cannot keep file '${file}' - restore it manually or use resolution='delete'."
			;;
		esac
	fi
else
	mcp_fail_invalid_args "File not found and not in conflict state: ${file}"
fi

remaining="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')"

# shellcheck disable=SC2016
mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--arg file "${file}" \
	--argjson remainingConflicts "${remaining}" \
	--arg summary "Marked ${file} as resolved. ${remaining} conflict(s) remaining." \
	'{success: $success, file: $file, remainingConflicts: $remainingConflicts, summary: $summary}')"
