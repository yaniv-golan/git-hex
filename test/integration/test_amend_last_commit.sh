#!/usr/bin/env bash
# Integration tests for gitHex.amendLastCommit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../common/env.sh"
. "${SCRIPT_DIR}/../common/assert.sh"
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_verify_framework
test_create_tmpdir

echo "=== Testing gitHex.amendLastCommit ==="

# ============================================================
# TEST: amend-last-commit with staged changes
# ============================================================
printf ' -> amend-last-commit amends with staged changes\n'

REPO="${TEST_TMPDIR}/amend-staged"
create_staged_changes_repo "${REPO}"

previous_hash="$(cd "${REPO}" && git rev-parse HEAD)"

result="$(run_tool gitHex.amendLastCommit "${REPO}" '{}')"

assert_json_field "${result}" '.success' "true" "amend should succeed"
assert_json_field "${result}" '.headBefore' "${previous_hash}" "headBefore should match"

new_hash="$(echo "${result}" | jq -r '.headAfter')"
assert_ne "${previous_hash}" "${new_hash}" "headAfter should differ from headBefore"

# Verify the file content was amended
file_content="$(cd "${REPO}" && git show HEAD:file.txt)"
assert_eq "modified" "${file_content}" "amended commit should contain modified content"

test_pass "amend-last-commit amends with staged changes"

# ============================================================
# TEST: amend-last-commit with new message
# ============================================================
printf ' -> amend-last-commit changes commit message\n'

REPO2="${TEST_TMPDIR}/amend-message"
create_test_repo "${REPO2}" 2

previous_hash="$(cd "${REPO2}" && git rev-parse HEAD)"
original_message="$(cd "${REPO2}" && git log -1 --format='%s' HEAD)"

result="$(run_tool gitHex.amendLastCommit "${REPO2}" '{"message": "New commit message"}')"

assert_json_field "${result}" '.success' "true" "amend should succeed"
assert_json_field "${result}" '.commitMessage' "New commit message" "commitMessage should be updated"

new_hash="$(echo "${result}" | jq -r '.headAfter')"
assert_ne "${previous_hash}" "${new_hash}" "headAfter should differ from headBefore"

test_pass "amend-last-commit changes commit message"

# ============================================================
# TEST: amend-last-commit with addAll flag
# ============================================================
printf ' -> amend-last-commit with addAll stages tracked files\n'

REPO3="${TEST_TMPDIR}/amend-addall"
create_test_repo "${REPO3}" 2

# Modify a tracked file without staging
echo "unstaged modification" > "${REPO3}/file1.txt"

previous_hash="$(cd "${REPO3}" && git rev-parse HEAD)"

result="$(run_tool gitHex.amendLastCommit "${REPO3}" '{"addAll": true, "message": "Amended with addAll"}')"

assert_json_field "${result}" '.success' "true" "amend should succeed"

# Verify the modification was included
file_content="$(cd "${REPO3}" && git show HEAD:file1.txt)"
assert_eq "unstaged modification" "${file_content}" "addAll should stage and include modification"

test_pass "amend-last-commit with addAll stages tracked files"

# ============================================================
# TEST: amend-last-commit fails without changes or message
# ============================================================
printf ' -> amend-last-commit fails without changes or message\n'

REPO4="${TEST_TMPDIR}/amend-nothing"
create_test_repo "${REPO4}" 2

if run_tool_expect_fail gitHex.amendLastCommit "${REPO4}" '{}'; then
	test_pass "amend-last-commit fails without changes or message"
else
	test_fail "should fail without changes or message"
fi

# ============================================================
# TEST: amend-last-commit fails on empty repo
# ============================================================
printf ' -> amend-last-commit fails on empty repo\n'

REPO5="${TEST_TMPDIR}/amend-empty"
mkdir -p "${REPO5}"
(cd "${REPO5}" && git init --initial-branch=main >/dev/null 2>&1 && git config user.email "test@example.com" && git config user.name "Test" && git config commit.gpgsign false)

if run_tool_expect_fail gitHex.amendLastCommit "${REPO5}" '{"message": "test"}'; then
	test_pass "amend-last-commit fails on empty repo"
else
	test_fail "should fail on empty repo"
fi

# ============================================================
# TEST: amend-last-commit fails during rebase
# ============================================================
printf ' -> amend-last-commit fails during rebase state\n'

REPO6="${TEST_TMPDIR}/amend-rebase"
create_conflict_scenario "${REPO6}"

# Start a rebase that will conflict
(cd "${REPO6}" && GIT_SEQUENCE_EDITOR=true git rebase -i main 2>/dev/null || true)

if run_tool_expect_fail gitHex.amendLastCommit "${REPO6}" '{"message": "test"}'; then
	test_pass "amend-last-commit fails during rebase state"
else
	test_fail "should fail during rebase state"
fi

# Cleanup rebase state
(cd "${REPO6}" && git rebase --abort 2>/dev/null || true)

echo ""
echo "All gitHex.amendLastCommit tests passed!"

