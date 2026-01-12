#!/usr/bin/env bash
# Unit tests for lib/stash.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/assert.sh disable=SC1091
source "${SCRIPT_DIR}/../common/assert.sh"
# shellcheck source=../../lib/stash.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/stash.sh"

setup_test_repo() {
	local repo
	repo="$(mktemp -d "${TMPDIR:-/tmp}/githex.unit.stash.XXXXXX")"
	git -C "${repo}" init -q
	git -C "${repo}" config user.email "test@test.com"
	git -C "${repo}" config user.name "Test User"
	echo "initial content" >"${repo}/file.txt"
	git -C "${repo}" add file.txt
	git -C "${repo}" commit -m "Initial commit" -q
	echo "${repo}"
}

cleanup_test_repo() {
	local repo="$1"
	rm -rf "${repo}" 2>/dev/null || true
}

test_should_stash_false_for_clean_repo() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	local result
	result="$(git_hex_should_stash "${repo}")"

	assert_eq "false" "${result}" "Clean repo should not need stash"
	test_pass "git_hex_should_stash returns false for clean repo"
}

test_should_stash_true_for_modified_file() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	# Modify tracked file
	echo "modified" >>"${repo}/file.txt"

	local result
	result="$(git_hex_should_stash "${repo}")"

	assert_eq "true" "${result}" "Modified file should require stash"
	test_pass "git_hex_should_stash returns true for modified file"
}

test_should_stash_true_for_staged_changes() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	# Stage a new file
	echo "new content" >"${repo}/new.txt"
	git -C "${repo}" add new.txt

	local result
	result="$(git_hex_should_stash "${repo}")"

	assert_eq "true" "${result}" "Staged changes should require stash"
	test_pass "git_hex_should_stash returns true for staged changes"
}

test_auto_stash_creates_stash() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	# Modify tracked file
	echo "modified" >>"${repo}/file.txt"

	local result
	result="$(git_hex_auto_stash "${repo}")"

	if [[ "${result}" != stash:* ]]; then
		test_fail "auto_stash should return stash info, got: ${result}"
	fi

	# Verify working tree is now clean
	if ! git -C "${repo}" diff --quiet -- 2>/dev/null; then
		test_fail "Working tree should be clean after auto_stash"
	fi

	test_pass "git_hex_auto_stash creates stash and cleans working tree"
}

test_auto_stash_returns_false_for_clean() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	local result
	result="$(git_hex_auto_stash "${repo}")"

	assert_eq "false" "${result}" "auto_stash should return false for clean repo"
	test_pass "git_hex_auto_stash returns false for clean repo"
}

test_restore_stash_restores_changes() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	# Modify tracked file
	echo "modified content" >>"${repo}/file.txt"
	local original_content
	original_content="$(cat "${repo}/file.txt")"

	# Stash
	local stash_info
	stash_info="$(git_hex_auto_stash "${repo}")"

	# Verify clean
	if ! git -C "${repo}" diff --quiet -- 2>/dev/null; then
		test_fail "Working tree should be clean after stash"
	fi

	# Restore
	local restore_result
	restore_result="$(git_hex_restore_stash "${repo}" "${stash_info}")"

	assert_eq "false" "${restore_result}" "Restore should succeed"

	# Verify content is back
	local restored_content
	restored_content="$(cat "${repo}/file.txt")"
	assert_eq "${original_content}" "${restored_content}" "Content should be restored"

	test_pass "git_hex_restore_stash restores changes"
}

test_restore_stash_noop_for_false() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	local result
	result="$(git_hex_restore_stash "${repo}" "false")"

	assert_eq "false" "${result}" "restore_stash with 'false' should return false"
	test_pass "git_hex_restore_stash is noop for false input"
}

echo "=== Running stash.sh unit tests ==="
test_should_stash_false_for_clean_repo
test_should_stash_true_for_modified_file
test_should_stash_true_for_staged_changes
test_auto_stash_creates_stash
test_auto_stash_returns_false_for_clean
test_restore_stash_restores_changes
test_restore_stash_noop_for_false
echo ""
echo "All stash.sh tests passed!"
