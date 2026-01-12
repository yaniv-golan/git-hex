#!/usr/bin/env bash
# Unit tests for lib/git-helpers.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/assert.sh disable=SC1091
source "${SCRIPT_DIR}/../common/assert.sh"
# shellcheck source=../../lib/git-helpers.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/git-helpers.sh"

# Mock mcp_fail_invalid_args since it's not available in unit tests
mcp_fail_invalid_args() {
	echo "ERROR: $1" >&2
	exit 1
}

setup_test_repo() {
	local repo
	repo="$(mktemp -d "${TMPDIR:-/tmp}/githex.unit.helpers.XXXXXX")"
	git -C "${repo}" init -q
	git -C "${repo}" config user.email "test@test.com"
	git -C "${repo}" config user.name "Test User"
	git -C "${repo}" commit --allow-empty -m "Initial commit" -q
	echo "${repo}"
}

cleanup_test_repo() {
	local repo="$1"
	rm -rf "${repo}" 2>/dev/null || true
}

test_get_git_dir_returns_path() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	local git_dir
	git_dir="$(git_hex_get_git_dir "${repo}")"

	assert_ne "" "${git_dir}" "Git dir should not be empty"
	if [ ! -d "${git_dir}" ]; then
		test_fail "Git dir should be a directory: ${git_dir}"
	fi

	test_pass "git_hex_get_git_dir returns valid path"
}

test_is_detached_head_false_on_branch() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	if git_hex_is_detached_head "${repo}"; then
		test_fail "Should not be detached HEAD on branch"
	fi

	test_pass "git_hex_is_detached_head returns false on branch"
}

test_is_detached_head_true_when_detached() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	# Detach HEAD
	git -C "${repo}" checkout --detach HEAD -q

	if ! git_hex_is_detached_head "${repo}"; then
		test_fail "Should be detached HEAD"
	fi

	test_pass "git_hex_is_detached_head returns true when detached"
}

test_get_in_progress_operation_none() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	local git_dir
	git_dir="$(git_hex_get_git_dir "${repo}")"

	local op
	op="$(git_hex_get_in_progress_operation_from_git_dir "${git_dir}")"

	assert_eq "" "${op}" "Should have no operation in progress"
	test_pass "git_hex_get_in_progress_operation_from_git_dir returns empty for clean repo"
}

test_is_safe_repo_relative_path_valid() {
	if ! git_hex_is_safe_repo_relative_path "src/file.txt"; then
		test_fail "src/file.txt should be valid"
	fi
	if ! git_hex_is_safe_repo_relative_path "file.txt"; then
		test_fail "file.txt should be valid"
	fi
	if ! git_hex_is_safe_repo_relative_path "a/b/c/d.txt"; then
		test_fail "a/b/c/d.txt should be valid"
	fi

	test_pass "git_hex_is_safe_repo_relative_path accepts valid paths"
}

test_is_safe_repo_relative_path_rejects_absolute() {
	if git_hex_is_safe_repo_relative_path "/etc/passwd"; then
		test_fail "/etc/passwd should be rejected"
	fi

	test_pass "git_hex_is_safe_repo_relative_path rejects absolute paths"
}

test_is_safe_repo_relative_path_rejects_traversal() {
	if git_hex_is_safe_repo_relative_path "../file.txt"; then
		test_fail "../file.txt should be rejected"
	fi
	if git_hex_is_safe_repo_relative_path "a/../b/file.txt"; then
		test_fail "a/../b/file.txt should be rejected"
	fi

	test_pass "git_hex_is_safe_repo_relative_path rejects traversal"
}

test_is_safe_repo_relative_path_rejects_drive_letter() {
	if git_hex_is_safe_repo_relative_path "C:/Windows/system32"; then
		test_fail "C:/Windows/system32 should be rejected"
	fi

	test_pass "git_hex_is_safe_repo_relative_path rejects drive letters"
}

test_parse_git_version() {
	local result
	result="$(git_hex_parse_git_version)"

	assert_ne "" "${result}" "Git version should not be empty"

	local major
	IFS=$'\t' read -r major _ _ <<<"${result}"

	# Git version should be at least 2.x
	if [ "${major}" -lt 2 ]; then
		test_fail "Git major version should be at least 2, got ${major}"
	fi

	test_pass "git_hex_parse_git_version parses version correctly"
}

test_is_shallow_repo_false() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	if git_hex_is_shallow_repo "${repo}"; then
		test_fail "Fresh repo should not be shallow"
	fi

	test_pass "git_hex_is_shallow_repo returns false for non-shallow repo"
}

echo "=== Running git-helpers.sh unit tests ==="
test_get_git_dir_returns_path
test_is_detached_head_false_on_branch
test_is_detached_head_true_when_detached
test_get_in_progress_operation_none
test_is_safe_repo_relative_path_valid
test_is_safe_repo_relative_path_rejects_absolute
test_is_safe_repo_relative_path_rejects_traversal
test_is_safe_repo_relative_path_rejects_drive_letter
test_parse_git_version
test_is_shallow_repo_false
echo ""
echo "All git-helpers.sh tests passed!"
