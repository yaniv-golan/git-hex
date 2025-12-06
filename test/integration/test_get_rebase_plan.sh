#!/usr/bin/env bash
# Integration tests for gitHex.getRebasePlan
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/env.sh disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"
# shellcheck source=../common/git_fixtures.sh disable=SC1091
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_verify_framework
test_create_tmpdir

echo "=== Testing gitHex.getRebasePlan ==="

# ============================================================
# TEST: get-rebase-plan returns correct structure
# ============================================================
printf ' -> get-rebase-plan returns valid JSON with commits\n'

REPO="${TEST_TMPDIR}/test-repo-1"
create_test_repo "${REPO}" 5

result="$(run_tool gitHex.getRebasePlan "${REPO}" '{"count": 3}')"

# Verify JSON structure
assert_json_field "${result}" '.success' "true" "should succeed"

plan_id="$(echo "${result}" | jq -r '.plan_id')"
assert_ne "" "${plan_id}" "plan_id should be present"
assert_ne "null" "${plan_id}" "plan_id should not be null"

assert_json_field "${result}" '.branch' "main" "branch should be main"

commits_count="$(echo "${result}" | jq -r '.commits | length')"
assert_eq "3" "${commits_count}" "should return 3 commits"

test_pass "get-rebase-plan returns valid structure"

# ============================================================
# TEST: get-rebase-plan with default count
# ============================================================
printf ' -> get-rebase-plan uses default count of 10\n'

REPO2="${TEST_TMPDIR}/test-repo-2"
create_test_repo "${REPO2}" 15

result="$(run_tool gitHex.getRebasePlan "${REPO2}" '{}')"

commits_count="$(echo "${result}" | jq -r '.commits | length')"
assert_eq "10" "${commits_count}" "should return 10 commits by default"

test_pass "get-rebase-plan uses default count"

# ============================================================
# TEST: get-rebase-plan fails on non-git directory
# ============================================================
printf ' -> get-rebase-plan fails on non-git directory\n'

NON_GIT="${TEST_TMPDIR}/not-a-repo"
mkdir -p "${NON_GIT}"

if run_tool_expect_fail gitHex.getRebasePlan "${NON_GIT}" '{}'; then
	test_pass "get-rebase-plan fails on non-git directory"
else
	test_fail "should fail on non-git directory"
fi

# ============================================================
# TEST: get-rebase-plan respects onto parameter
# ============================================================
printf ' -> get-rebase-plan respects onto parameter\n'

REPO3="${TEST_TMPDIR}/test-repo-3"
create_test_repo "${REPO3}" 5

result="$(run_tool gitHex.getRebasePlan "${REPO3}" '{"onto": "HEAD~2"}')"

commits_count="$(echo "${result}" | jq -r '.commits | length')"
assert_eq "2" "${commits_count}" "should return 2 commits when onto=HEAD~2"

test_pass "get-rebase-plan respects onto parameter"

# ============================================================
# TEST: get-rebase-plan handles special characters in commit messages
# ============================================================
printf ' -> get-rebase-plan handles special characters in messages\n'

REPO4="${TEST_TMPDIR}/test-repo-4"
mkdir -p "${REPO4}"
(
	cd "${REPO4}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "file1" >file1.txt
	git add file1.txt
	git commit -m "Initial commit" >/dev/null

	# Test pipes and quotes
	echo "file2" >file2.txt
	git add file2.txt
	git commit -m 'Message with |pipes| and "quotes"' >/dev/null

	# Test dollars and backticks
	echo "file3" >file3.txt
	git add file3.txt
	# shellcheck disable=SC2016
	git commit -m 'Message with $dollars and `backticks`' >/dev/null

	# Test tabs (the trickiest case)
	echo "file4" >file4.txt
	git add file4.txt
	git commit -m $'Message with\ttabs\tin it' >/dev/null
)

result="$(run_tool gitHex.getRebasePlan "${REPO4}" '{"count": 4}')"

# Verify we got 3 commits (not counting the base)
commits_count="$(echo "${result}" | jq -r '.commits | length')"
assert_eq "3" "${commits_count}" "should return 3 commits"

# Verify the pipe character is preserved in the subject
subject1="$(echo "${result}" | jq -r '.commits[0].subject')"
echo "${subject1}" | grep -q '|pipes|' || test_fail "pipe chars should be preserved in subject"

# Verify the tab character is preserved (jq will show it as \t in raw mode, but the actual value has the tab)
subject3="$(echo "${result}" | jq -r '.commits[2].subject')"
# Check that the subject contains "tabs" and "in it" - if parsing broke, we'd get truncated/wrong data
echo "${subject3}" | grep -q 'tabs' || test_fail "tab-containing message should be parsed correctly"
echo "${subject3}" | grep -q 'in it' || test_fail "full message after tab should be preserved"

test_pass "get-rebase-plan handles special characters in messages"

echo ""
echo "All gitHex.getRebasePlan tests passed!"
