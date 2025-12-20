#!/usr/bin/env bash
# Shared git-related helpers for git-hex tools.

set -euo pipefail

git_hex_require_repo() {
	local repo_path="$1"
	if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
		mcp_fail_invalid_args "Not a git repository at ${repo_path}"
	fi
	if [ "$(git -C "${repo_path}" rev-parse --is-bare-repository 2>/dev/null || echo "false")" = "true" ]; then
		mcp_fail_invalid_args "Bare repositories are not supported"
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
	rebase) mcp_fail_invalid_args "Repository is in a rebase state. Please resolve or abort it first." ;;
	cherry-pick) mcp_fail_invalid_args "Repository is in a cherry-pick state. Please resolve or abort it first." ;;
	revert) mcp_fail_invalid_args "Repository is in a revert state. Please resolve or abort it first." ;;
	merge) mcp_fail_invalid_args "Repository is in a merge state. Please resolve or abort it first." ;;
	bisect) mcp_fail_invalid_args "Repository is in a bisect state. Please reset it first (git bisect reset)." ;;
	esac
}

git_hex_require_clean_worktree_tracked() {
	local repo_path="$1"

	if ! git -C "${repo_path}" diff --quiet -- 2>/dev/null || ! git -C "${repo_path}" diff --cached --quiet -- 2>/dev/null; then
		mcp_fail_invalid_args "Repository has uncommitted changes. Please commit or stash them first."
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
		mcp_fail -32603 "${failure_prefix}: GPG signing error. Check your signing configuration or use 'git config commit.gpgsign false' to disable.${extra_suffix}"
	elif printf '%s' "${commit_error}" | grep -qi "hook\\|pre-commit\\|commit-msg"; then
		mcp_fail -32603 "${failure_prefix}: A git hook rejected the commit. Check your pre-commit or commit-msg hooks.${extra_suffix}"
	else
		local error_hint="${commit_error%%$'\n'*}"
		mcp_fail -32603 "${failure_prefix}: ${error_hint}${extra_suffix}"
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

	reason="$(_git_hex_repo_relative_path_error_reason "${path}")"
	case "${reason}" in
	null_bytes) mcp_fail_invalid_args "Null bytes are not allowed in paths" ;;
	absolute) mcp_fail_invalid_args "Absolute paths are not allowed" ;;
	traversal) mcp_fail_invalid_args "Path traversal is not allowed" ;;
	drive_letter) mcp_fail_invalid_args "Drive-letter paths are not allowed; use repo-relative POSIX paths" ;;
	"") return 0 ;;
	*) mcp_fail_invalid_args "Invalid path" ;;
	esac
}
