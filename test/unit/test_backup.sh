#!/usr/bin/env bash
# Unit tests for lib/backup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/assert.sh disable=SC1091
source "${SCRIPT_DIR}/../common/assert.sh"
# shellcheck source=../../lib/backup.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/backup.sh"

# Mock mcp_output since it's not available in unit tests
# git_hex_error calls mcp_output which outputs JSON and exits
mcp_output() {
	echo "$1"
}

# Override git_hex_error for testing - capture error and exit
git_hex_error() {
	local json
	json="$(git_hex_error_json "$@")"
	echo "${json}"
	exit 0
}

setup_test_repo() {
	local repo
	repo="$(mktemp -d "${TMPDIR:-/tmp}/githex.unit.backup.XXXXXX")"
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

test_create_backup_ref_creates_ref() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	local backup_ref
	backup_ref="$(git_hex_create_backup "${repo}" "test-op")"

	assert_ne "" "${backup_ref}" "Backup ref should not be empty"

	# Verify the ref exists
	if ! git -C "${repo}" rev-parse "refs/${backup_ref}" >/dev/null 2>&1; then
		test_fail "Backup ref should exist: refs/${backup_ref}"
	fi

	test_pass "git_hex_create_backup creates backup ref"
}

test_create_backup_ref_points_to_head() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	local head_before
	head_before="$(git -C "${repo}" rev-parse HEAD)"

	local backup_ref
	backup_ref="$(git_hex_create_backup "${repo}" "test-op")"

	local backup_hash
	backup_hash="$(git -C "${repo}" rev-parse "refs/${backup_ref}")"

	assert_eq "${head_before}" "${backup_hash}" "Backup ref should point to HEAD"
	test_pass "git_hex_create_backup points to HEAD"
}

test_get_last_backup_returns_info() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	git_hex_create_backup "${repo}" "myop" >/dev/null

	local info
	info="$(git_hex_get_last_backup "${repo}")"

	assert_ne "" "${info}" "Last backup info should not be empty"
	assert_contains "${info}" "myop" "Last backup should contain operation name"

	test_pass "git_hex_get_last_backup returns backup info"
}

test_get_last_backup_empty_for_no_backups() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	local info
	info="$(git_hex_get_last_backup "${repo}")"

	assert_eq "" "${info}" "Last backup should be empty when no backups exist"
	test_pass "git_hex_get_last_backup returns empty for no backups"
}

test_record_last_head_creates_ref() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	# Create a backup first
	git_hex_create_backup "${repo}" "test-op" >/dev/null

	# Make a new commit
	git -C "${repo}" commit --allow-empty -m "Second commit" -q
	local new_head
	new_head="$(git -C "${repo}" rev-parse HEAD)"

	# Record the new head
	git_hex_record_last_head "${repo}" "${new_head}"

	# Check that last-head ref was created
	local last_head_refs
	last_head_refs="$(git -C "${repo}" for-each-ref --format='%(refname)' refs/git-hex/last-head/ 2>/dev/null || true)"

	assert_ne "" "${last_head_refs}" "Last head ref should exist"
	test_pass "git_hex_record_last_head creates last-head ref"
}

test_list_backups_returns_refs() {
	local repo
	repo="$(setup_test_repo)"
	trap 'cleanup_test_repo '"'${repo}'"'' EXIT

	git_hex_create_backup "${repo}" "op1" >/dev/null
	sleep 1 # Ensure different timestamps
	git_hex_create_backup "${repo}" "op2" >/dev/null

	local backups
	backups="$(git_hex_list_backups "${repo}" 10)"

	assert_ne "" "${backups}" "Backup list should not be empty"
	# Should have at least 2 entries
	local count
	count="$(echo "${backups}" | wc -l | tr -d ' ')"
	if [ "${count}" -lt 2 ]; then
		test_fail "Should have at least 2 backups, got ${count}"
	fi

	test_pass "git_hex_list_backups returns backup refs"
}

echo "=== Running backup.sh unit tests ==="
test_create_backup_ref_creates_ref
test_create_backup_ref_points_to_head
test_get_last_backup_returns_info
test_get_last_backup_empty_for_no_backups
test_record_last_head_creates_ref
test_list_backups_returns_refs
echo ""
echo "All backup.sh tests passed!"
