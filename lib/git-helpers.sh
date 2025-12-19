#!/usr/bin/env bash
# Shared git-related helpers for git-hex tools.

set -euo pipefail

git_hex_require_repo() {
	local repo_path="$1"
	if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
		mcp_fail_invalid_args "Not a git repository at ${repo_path}"
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
	if [ -f "${git_dir}/MERGE_HEAD" ]; then
		printf 'merge\n'
		return 0
	fi
	printf '\n'
	return 0
}

git_hex_parse_git_version() {
	local git_version_raw
	git_version_raw="$(git --version | sed 's/git version //')"

	local git_major git_minor
	git_major="$(echo "${git_version_raw}" | cut -d. -f1)"
	git_minor="$(echo "${git_version_raw}" | cut -d. -f2)"
	git_major="${git_major%%[^0-9]*}"
	git_minor="${git_minor%%[^0-9]*}"
	git_minor="${git_minor:-0}"

	printf '%s\t%s\t%s\n' "${git_major}" "${git_minor}" "${git_version_raw}"
}

git_hex_is_safe_repo_relative_path() {
	local path="$1"

	local orig_len clean_len
	orig_len="$(printf '%s' "${path}" | LC_ALL=C wc -c | tr -d ' ')"
	clean_len="$(printf '%s' "${path}" | LC_ALL=C tr -d '\0' | wc -c | tr -d ' ')"
	if [ "${orig_len}" -ne "${clean_len}" ]; then
		return 1
	fi
	if [[ "${path}" == /* ]]; then
		return 1
	fi
	if [[ "${path}" == "../"* || "${path}" == ".." || "${path}" == *"/.."* || "${path}" == *"/../"* ]]; then
		return 1
	fi
	case "${path}" in
	[A-Za-z]:/* | [A-Za-z]:\\*)
		return 1
		;;
	esac
	return 0
}

git_hex_require_safe_repo_relative_path() {
	local path="$1"

	local orig_len clean_len
	orig_len="$(printf '%s' "${path}" | LC_ALL=C wc -c | tr -d ' ')"
	clean_len="$(printf '%s' "${path}" | LC_ALL=C tr -d '\0' | wc -c | tr -d ' ')"
	if [ "${orig_len}" -ne "${clean_len}" ]; then
		mcp_fail_invalid_args "Null bytes are not allowed in paths"
	fi
	if [[ "${path}" == /* ]]; then
		mcp_fail_invalid_args "Absolute paths are not allowed"
	fi
	if [[ "${path}" == "../"* || "${path}" == ".." || "${path}" == *"/.."* || "${path}" == *"/../"* ]]; then
		mcp_fail_invalid_args "Path traversal is not allowed"
	fi
	# Reject Windows-style drive letter paths to avoid ambiguity
	case "${path}" in
	[A-Za-z]:/* | [A-Za-z]:\\*)
		mcp_fail_invalid_args "Drive-letter paths are not allowed; use repo-relative POSIX paths"
		;;
	esac
}
