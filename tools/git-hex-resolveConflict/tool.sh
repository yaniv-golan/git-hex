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
mcp_log_info "git-hex" "Resolving conflict for ${file} (resolution=${resolution})"

# Directory guard
if [ -d "${repo_path}/${file}" ]; then
	git_hex_error "INVALID_PATH" "Path '${file}' is a directory, not a file" \
		"Specify a file path, not a directory"
fi

# Determine conflict status for the file
unmerged="$(git -C "${repo_path}" ls-files -u -- "${file}" 2>/dev/null || true)"

if [ -z "${unmerged}" ] && [ ! -f "${repo_path}/${file}" ]; then
	git_hex_error "FILE_NOT_FOUND" "File not found and not in conflict state: ${file}" \
		"Check the file path is correct" \
		"Use getConflictStatus to see conflicting files"
fi

if [ -f "${repo_path}/${file}" ]; then
	if [ -z "${unmerged}" ]; then
		git_hex_error "NOT_IN_CONFLICT" "File not in conflict state: ${file}" \
			"This file does not have conflicts to resolve" \
			"Use getConflictStatus to see conflicting files"
	fi
	if [ "${resolution}" = "delete" ]; then
		git -C "${repo_path}" rm -f -- "${file}" >/dev/null 2>&1
	else
		# Detect all common conflict marker lines (including diff3's "|||||||").
		if grep -qE '^(<<<<<<<|=======|>>>>>>>|[|]{7})' -- "${repo_path}/${file}" 2>/dev/null; then
			git_hex_error "CONFLICT_MARKERS_PRESENT" "File still contains conflict markers." \
				"Edit the file to resolve all <<<<<<< / ======= / >>>>>>> markers" \
				"Then call resolveConflict again"
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
				git_hex_error "GIT_ERROR" "Failed to restore '${file}' from theirs" \
					"Manual resolution required" \
					"Try 'git checkout --theirs -- ${file}' manually"
			fi
			if ! git -C "${repo_path}" add -- "${file}" >/dev/null 2>&1; then
				git_hex_error "GIT_ERROR" "Failed to stage '${file}' after restore" \
					"Manual resolution required" \
					"Try 'git add -- ${file}' manually"
			fi
			;;
		"1,2,")
			# deleted_by_them: restore ours
			if ! git -C "${repo_path}" checkout --ours -- "${file}" >/dev/null 2>&1; then
				git_hex_error "GIT_ERROR" "Failed to restore '${file}' from ours" \
					"Manual resolution required" \
					"Try 'git checkout --ours -- ${file}' manually"
			fi
			if ! git -C "${repo_path}" add -- "${file}" >/dev/null 2>&1; then
				git_hex_error "GIT_ERROR" "Failed to stage '${file}' after restore" \
					"Manual resolution required" \
					"Try 'git add -- ${file}' manually"
			fi
			;;
		*)
			git_hex_error "CANNOT_KEEP_FILE" "Cannot keep file '${file}'" \
				"Restore it manually or use resolution='delete'" \
				"Check getConflictStatus for conflict type details"
			;;
		esac
	fi
else
	git_hex_error "FILE_NOT_FOUND" "File not found and not in conflict state: ${file}" \
		"Check the file path is correct" \
		"Use getConflictStatus to see conflicting files"
fi

remaining="0"
while  IFS= read -r -d '' _conflict_file; do
	remaining="$((remaining + 1))"
done  < <(git -C "${repo_path}" diff --name-only --diff-filter=U -z 2>/dev/null || true)

# Build and emit result (mcp_result_success wraps in {success: true, result: ...} envelope)
# shellcheck disable=SC2016
result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--arg file "${file}" \
	--argjson remainingConflicts "${remaining}" \
	--arg summary "Marked ${file} as resolved. ${remaining} conflict(s) remaining." \
	'{file: $file, remainingConflicts: $remainingConflicts, summary: $summary}')"
mcp_result_success "${result}"
