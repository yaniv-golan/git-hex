#!/usr/bin/env bash
# Shared git-related helpers for git-hex tools.

set -euo pipefail

# ============================================================================
# Error Codes (string constants for discoverability; use directly if preferred)
# These are intentionally defined but unused - they serve as documentation
# for the error codes that tools can emit via git_hex_error().
# ============================================================================

# shellcheck disable=SC2034
readonly GIT_HEX_ERR_REBASE_IN_PROGRESS="REBASE_IN_PROGRESS"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_MERGE_IN_PROGRESS="MERGE_IN_PROGRESS"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_CHERRY_PICK_IN_PROGRESS="CHERRY_PICK_IN_PROGRESS"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_REVERT_IN_PROGRESS="REVERT_IN_PROGRESS"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_BISECT_IN_PROGRESS="BISECT_IN_PROGRESS"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_NOT_A_GIT_REPO="NOT_A_GIT_REPO"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_BARE_REPO="BARE_REPO"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_UNCOMMITTED_CHANGES="UNCOMMITTED_CHANGES"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_STASH_REQUIRED="STASH_REQUIRED"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_INVALID_COMMIT="INVALID_COMMIT"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_BRANCH_NOT_FOUND="BRANCH_NOT_FOUND"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_INVALID_REF="INVALID_REF"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_FILE_NOT_FOUND="FILE_NOT_FOUND"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_CONFLICT_MARKERS="CONFLICT_MARKERS"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_IS_DIRECTORY="IS_DIRECTORY"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_FILE_NOT_IN_CONFLICT="FILE_NOT_IN_CONFLICT"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_INVALID_ARGUMENT="INVALID_ARGUMENT"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_MISSING_ARGUMENT="MISSING_ARGUMENT"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_INVALID_PATH="INVALID_PATH"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_OPERATION_FAILED="OPERATION_FAILED"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_MERGE_COMMIT="MERGE_COMMIT"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_ROOT_COMMIT="ROOT_COMMIT"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_GPG_ERROR="GPG_ERROR"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_HOOK_REJECTED="HOOK_REJECTED"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_NO_STAGED_CHANGES="NO_STAGED_CHANGES"
# shellcheck disable=SC2034
readonly GIT_HEX_ERR_NO_COMMITS="NO_COMMITS"

# ============================================================================
# Error Output Functions
# ============================================================================

# Output a user-friendly error (does NOT exit - caller must handle)
# Usage: git_hex_error_json "ERROR_CODE" "Message" ["Suggestion1" "Suggestion2" ...]
# Returns: JSON string on stdout
# Note: Suggestions must not contain null bytes
git_hex_error_json() {
	local code="$1"
	local message="$2"
	shift 2
	local suggestions=("$@")

	local json_tool="${MCPBASH_JSON_TOOL_BIN:-jq}"

	if [[ ${#suggestions[@]} -eq 0 ]]; then
		# shellcheck disable=SC2016  # $code, $msg are jq variables, not bash
		"$json_tool" -n \
			--arg code "$code" \
			--arg msg "$message" \
			'{success: false, error: {code: $code, message: $msg}}'
	else
		# Use null-delimited format to handle suggestions with newlines
		local suggestions_json
		suggestions_json=$(printf '%s\0' "${suggestions[@]}" | "$json_tool" -Rs 'split("\u0000") | .[:-1]')
		# shellcheck disable=SC2016  # $code, $msg, $sug are jq variables, not bash
		"$json_tool" -n \
			--arg code "$code" \
			--arg msg "$message" \
			--argjson sug "$suggestions_json" \
			'{success: false, error: {code: $code, message: $msg, suggestions: $sug}}'
	fi
}

# Output error as MCP CallToolResult and exit (convenience wrapper)
# Usage: git_hex_error "ERROR_CODE" "Message" ["Suggestion1" "Suggestion2" ...]
# Note: Uses isError: false so Claude won't show "Failed to call tool" banner
git_hex_error() {
	local error_json
	error_json="$(git_hex_error_json "$@")"

	local json_tool="${MCPBASH_JSON_TOOL_BIN:-jq}"

	# Emit MCP CallToolResult with error in structuredContent
	# isError: false prevents the "Failed to call tool" banner in Claude Desktop
	# shellcheck disable=SC2016  # $err is a jq variable, not bash
	"$json_tool" -n \
		--argjson err "$error_json" \
		'{
			content: [{type: "text", text: $err.error.message}],
			structuredContent: $err,
			isError: false
		}'
	exit 0
}

# ============================================================================
# Repository Validation
# ============================================================================

git_hex_require_repo() {
	local repo_path="$1"
	if command -v mcp_log_debug >/dev/null 2>&1; then
		mcp_log_debug "git-hex" "Validating git repository at ${repo_path}"
	fi
	if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
		git_hex_error "NOT_A_GIT_REPO" "Not a git repository at ${repo_path}" \
			"Ensure the path points to a valid git repository" \
			"Initialize with 'git init' if needed"
	fi
	if [ "$(git -C "${repo_path}" rev-parse --is-bare-repository 2>/dev/null || echo "false")" = "true" ]; then
		git_hex_error "BARE_REPO" "Bare repositories are not supported" \
			"Clone the repository to a working directory instead"
	fi
}

git_hex_get_git_dir() {
	local repo_path="$1"
	local git_dir
	git_dir="$(git -C "${repo_path}" rev-parse --git-dir 2>/dev/null || true)"
	[ -n "${git_dir}" ] || return 1
	case "${git_dir}" in
	/*) printf '%s\n' "${git_dir}" ;;
	*) printf '%s\n' "${repo_path}/${git_dir}" ;;
	esac
}

git_hex_get_in_progress_operation_from_git_dir() {
	local git_dir="$1"

	if command -v mcp_log_debug >/dev/null 2>&1; then
		mcp_log_debug "git-hex" "Checking for in-progress operations in ${git_dir}"
	fi

	if [ -d "${git_dir}/rebase-merge" ] || [ -d "${git_dir}/rebase-apply" ]; then
		printf 'rebase\n'
		return 0
	fi
	if [ -f "${git_dir}/CHERRY_PICK_HEAD" ]; then
		printf 'cherry-pick\n'
		return 0
	fi
	if [ -f "${git_dir}/REVERT_HEAD" ]; then
		printf 'revert\n'
		return 0
	fi
	if [ -f "${git_dir}/MERGE_HEAD" ]; then
		printf 'merge\n'
		return 0
	fi
	if [ -f "${git_dir}/BISECT_LOG" ] || [ -f "${git_dir}/BISECT_START" ] || [ -f "${git_dir}/BISECT_NAMES" ]; then
		printf 'bisect\n'
		return 0
	fi
	printf '\n'
	return 0
}

git_hex_is_detached_head() {
	local repo_path="$1"
	local branch

	branch="$(git -C "${repo_path}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
	[ -z "${branch}" ] && return 0
	[ "${branch}" = "HEAD" ] && return 0
	return 1
}

git_hex_require_no_in_progress_operation() {
	local operation="$1"

	case "${operation}" in
	"") return 0 ;;
	rebase) git_hex_error "REBASE_IN_PROGRESS" "Repository is in a rebase state." \
		"Use getConflictStatus to check status" \
		"Then use resolveConflict/continueOperation or abortOperation" ;;
	cherry-pick) git_hex_error "CHERRY_PICK_IN_PROGRESS" "Repository is in a cherry-pick state." \
		"Use getConflictStatus to check status" \
		"Then use resolveConflict/continueOperation or abortOperation" ;;
	revert) git_hex_error "REVERT_IN_PROGRESS" "Repository is in a revert state." \
		"Use getConflictStatus to check status" \
		"Then use resolveConflict/continueOperation or abortOperation" ;;
	merge) git_hex_error "MERGE_IN_PROGRESS" "Repository is in a merge state." \
		"Use getConflictStatus to check status" \
		"Then use resolveConflict/continueOperation or abortOperation" ;;
	bisect) git_hex_error "BISECT_IN_PROGRESS" "Repository is in a bisect state." \
		"Run 'git bisect reset' to exit bisect mode" \
		"Then retry the git-hex operation" ;;
	esac
}

git_hex_require_clean_worktree_tracked() {
	local repo_path="$1"

	if ! git -C "${repo_path}" diff --quiet -- 2>/dev/null || ! git -C "${repo_path}" diff --cached --quiet -- 2>/dev/null; then
		git_hex_error "UNCOMMITTED_CHANGES" "Repository has uncommitted changes." \
			"Use autoStash=true to automatically stash and restore changes" \
			"Or commit/stash changes manually first"
	fi
}

git_hex_get_conflicting_files_json() {
	local repo_path="$1"

	local json_tool
	json_tool="${MCPBASH_JSON_TOOL_BIN:-jq}"

	local conflicting_json="[]"
	while IFS= read -r -d '' conflict_file; do
		[ -z "${conflict_file}" ] && continue
		# shellcheck disable=SC2016
		conflicting_json="$(printf '%s' "${conflicting_json}" | "${json_tool}" --arg f "${conflict_file}" '. + [$f]')"
	done < <(git -C "${repo_path}" diff --name-only --diff-filter=U -z 2>/dev/null || true)

	printf '%s' "${conflicting_json}"
}

git_hex_parse_git_version() {
	local git_version_raw
	git_version_raw="$(git --version | sed 's/git version //')"

	local git_major git_minor
	git_major="$(printf '%s' "${git_version_raw}" | cut -d. -f1)"
	git_minor="$(printf '%s' "${git_version_raw}" | cut -d. -f2)"
	git_major="${git_major%%[^0-9]*}"
	git_minor="${git_minor%%[^0-9]*}"
	git_minor="${git_minor:-0}"

	printf '%s\t%s\t%s\n' "${git_major}" "${git_minor}" "${git_version_raw}"
}

git_hex_fail_commit_error() {
	local failure_prefix="$1"
	local commit_error="${2:-}"
	local extra_suffix="${3:-}"

	if printf '%s' "${commit_error}" | grep -qi "gpg\\|signing\\|sign"; then
		git_hex_error "GPG_ERROR" "${failure_prefix}: GPG signing error.${extra_suffix}" \
			"Disable GPG signing with signCommits=false" \
			"Or fix GPG configuration"
	elif printf '%s' "${commit_error}" | grep -qi "hook\\|pre-commit\\|commit-msg"; then
		git_hex_error "HOOK_REJECTED" "${failure_prefix}: A git hook rejected the commit.${extra_suffix}" \
			"Check pre-commit or commit-msg hooks" \
			"Fix the issue or bypass with --no-verify if appropriate"
	else
		local error_hint="${commit_error%%$'\n'*}"
		git_hex_error "COMMIT_FAILED" "${failure_prefix}: ${error_hint}${extra_suffix}" \
			"Check the error message for details"
	fi
}

git_hex_is_shallow_repo() {
	local repo_path="$1"
	[ "$(git -C "${repo_path}" rev-parse --is-shallow-repository 2>/dev/null || echo "false")" = "true" ]
}

git_hex_is_safe_repo_relative_path() {
	local path="$1"

	_git_hex_repo_relative_path_error_reason "${path}" >/dev/null 2>&1
}

_git_hex_repo_relative_path_error_reason() {
	local path="$1"

	local orig_len clean_len
	orig_len="$(printf '%s' "${path}" | LC_ALL=C wc -c | tr -d ' ')"
	clean_len="$(printf '%s' "${path}" | LC_ALL=C tr -d '\0' | wc -c | tr -d ' ')"
	if [ "${orig_len}" -ne "${clean_len}" ]; then
		printf 'null_bytes\n'
		return 1
	fi
	if [[ "${path}" == /* ]]; then
		printf 'absolute\n'
		return 1
	fi
	# Reject traversal segments, but allow filenames that merely start with ".." (e.g., "dir/..backup").
	if [[ "${path}" == "../"* || "${path}" == ".." || "${path}" == *"/../"* || "${path}" == */.. ]]; then
		printf 'traversal\n'
		return 1
	fi
	case "${path}" in
	[A-Za-z]:/* | [A-Za-z]:\\*)
		printf 'drive_letter\n'
		return 1
		;;
	esac
	printf '\n'
	return 0
}

git_hex_require_safe_repo_relative_path() {
	local path="$1"

	if command -v mcp_log_debug >/dev/null 2>&1; then
		mcp_log_debug "git-hex" "Validating repo-relative path: ${path}"
	fi

	reason="$(_git_hex_repo_relative_path_error_reason "${path}")"
	case "${reason}" in
	null_bytes) git_hex_error "INVALID_PATH" "Null bytes are not allowed in paths" \
		"Use a valid file path without null characters" ;;
	absolute) git_hex_error "INVALID_PATH" "Absolute paths are not allowed" \
		"Use a repo-relative path instead (e.g., 'src/file.txt' not '/full/path/src/file.txt')" ;;
	traversal) git_hex_error "INVALID_PATH" "Path traversal is not allowed" \
		"Use a direct path without '..' components" ;;
	drive_letter) git_hex_error "INVALID_PATH" "Drive-letter paths are not allowed" \
		"Use repo-relative POSIX paths (e.g., 'src/file.txt' not 'C:/path/file.txt')" ;;
	"") return 0 ;;
	*) git_hex_error "INVALID_PATH" "Invalid path" \
		"Use a valid repo-relative file path" ;;
	esac
}
