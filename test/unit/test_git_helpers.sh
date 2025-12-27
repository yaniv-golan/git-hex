#!/usr/bin/env bash
# Unit tests for lib/git-helpers.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/assert.sh disable=SC1091
source "${SCRIPT_DIR}/../common/assert.sh"
# shellcheck source=../../lib/git-helpers.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/git-helpers.sh"

# Track last error for assertions
_LAST_ERROR_JSON=""

# Helper to run a function and capture error response
# git_hex_error outputs MCP CallToolResult JSON then exits 0
run_expecting_error() {
	_LAST_ERROR_JSON=""
	# Run in subshell to catch the exit; capture stdout
	_LAST_ERROR_JSON="$("$@" 2>/dev/null)" || true
}

# Assert error response has expected code
# Note: git_hex_error outputs MCP CallToolResult with error in structuredContent
assert_error_code() {
	local expected="$1"
	local actual
	actual="$(echo "${_LAST_ERROR_JSON}" | "${MCPBASH_JSON_TOOL_BIN:-jq}" -r '.structuredContent.error.code // empty' 2>/dev/null || true)"
	if [ "${actual}" != "${expected}" ]; then
		test_fail "Expected error code '${expected}', got '${actual}'"
	fi
}

# Assert error response has success=false in structuredContent
assert_error_response() {
	local success
	success="$(echo "${_LAST_ERROR_JSON}" | "${MCPBASH_JSON_TOOL_BIN:-jq}" -r '.structuredContent.success' 2>/dev/null || true)"
	if [ "${success}" != "false" ]; then
		test_fail "Expected success=false, got '${success}'"
	fi
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

# ============================================================================
# Error Response Tests
# ============================================================================

test_error_json_structure() {
	local json
	json="$(git_hex_error_json "TEST_CODE" "Test message")"

	local success
	success="$(echo "${json}" | "${MCPBASH_JSON_TOOL_BIN:-jq}" -r '.success' 2>/dev/null)"
	assert_eq "false" "${success}" "success should be false"

	local code
	code="$(echo "${json}" | "${MCPBASH_JSON_TOOL_BIN:-jq}" -r '.error.code' 2>/dev/null)"
	assert_eq "TEST_CODE" "${code}" "error code should match"

	local message
	message="$(echo "${json}" | "${MCPBASH_JSON_TOOL_BIN:-jq}" -r '.error.message' 2>/dev/null)"
	assert_eq "Test message" "${message}" "error message should match"

	test_pass "git_hex_error_json creates correct structure"
}

test_error_json_with_suggestions() {
	local json
	json="$(git_hex_error_json "TEST_CODE" "Test message" "Suggestion 1" "Suggestion 2")"

	local count
	count="$(echo "${json}" | "${MCPBASH_JSON_TOOL_BIN:-jq}" -r '.error.suggestions | length' 2>/dev/null)"
	assert_eq "2" "${count}" "should have 2 suggestions"

	local sug1
	sug1="$(echo "${json}" | "${MCPBASH_JSON_TOOL_BIN:-jq}" -r '.error.suggestions[0]' 2>/dev/null)"
	assert_eq "Suggestion 1" "${sug1}" "first suggestion should match"

	test_pass "git_hex_error_json includes suggestions"
}

test_require_repo_error_not_git_repo() {
	local tmpdir
	tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/githex.unit.notgit.XXXXXX")"
	trap 'rm -rf '"'${tmpdir}'"'' EXIT

	run_expecting_error git_hex_require_repo "${tmpdir}"
	assert_error_response
	assert_error_code "NOT_A_GIT_REPO"

	test_pass "git_hex_require_repo returns NOT_A_GIT_REPO for non-git directory"
}

test_require_no_in_progress_operation_rebase_error() {
	run_expecting_error git_hex_require_no_in_progress_operation "rebase"
	assert_error_response
	assert_error_code "REBASE_IN_PROGRESS"

	test_pass "git_hex_require_no_in_progress_operation returns REBASE_IN_PROGRESS"
}

test_require_no_in_progress_operation_merge_error() {
	run_expecting_error git_hex_require_no_in_progress_operation "merge"
	assert_error_response
	assert_error_code "MERGE_IN_PROGRESS"

	test_pass "git_hex_require_no_in_progress_operation returns MERGE_IN_PROGRESS"
}

test_require_no_in_progress_operation_cherry_pick_error() {
	run_expecting_error git_hex_require_no_in_progress_operation "cherry-pick"
	assert_error_response
	assert_error_code "CHERRY_PICK_IN_PROGRESS"

	test_pass "git_hex_require_no_in_progress_operation returns CHERRY_PICK_IN_PROGRESS"
}

test_require_no_in_progress_operation_none_succeeds() {
	# Should return 0 (success) with no output
	if ! git_hex_require_no_in_progress_operation "" >/dev/null 2>&1; then
		test_fail "Should succeed when no operation in progress"
	fi

	test_pass "git_hex_require_no_in_progress_operation succeeds with no operation"
}

test_require_safe_path_error_absolute() {
	run_expecting_error git_hex_require_safe_repo_relative_path "/etc/passwd"
	assert_error_response
	assert_error_code "INVALID_PATH"

	test_pass "git_hex_require_safe_repo_relative_path returns INVALID_PATH for absolute"
}

test_require_safe_path_error_traversal() {
	run_expecting_error git_hex_require_safe_repo_relative_path "../secret"
	assert_error_response
	assert_error_code "INVALID_PATH"

	test_pass "git_hex_require_safe_repo_relative_path returns INVALID_PATH for traversal"
}

echo "=== Running git-helpers.sh unit tests ==="

echo "--- Error Response Tests ---"
test_error_json_structure
test_error_json_with_suggestions
test_require_repo_error_not_git_repo
test_require_no_in_progress_operation_rebase_error
test_require_no_in_progress_operation_merge_error
test_require_no_in_progress_operation_cherry_pick_error
test_require_no_in_progress_operation_none_succeeds
test_require_safe_path_error_absolute
test_require_safe_path_error_traversal

echo "--- Existing Tests ---"
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
