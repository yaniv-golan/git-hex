#!/usr/bin/env bash
# Integration tests for gitHex.performRebase
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../common/env.sh"
. "${SCRIPT_DIR}/../common/assert.sh"
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_verify_framework
test_create_tmpdir

echo "=== Testing gitHex.performRebase ==="

# ============================================================
# TEST: perform-rebase succeeds with no conflicts
# ============================================================
printf ' -> perform-rebase succeeds with clean rebase\n'

REPO="${TEST_TMPDIR}/rebase-clean"
create_branch_scenario "${REPO}"

result="$(run_tool gitHex.performRebase "${REPO}" '{"onto": "main"}' 60)"

assert_json_field "${result}" '.success' "true" "rebase should succeed"

test_pass "perform-rebase succeeds with clean rebase"

# ============================================================
# TEST: perform-rebase aborts on conflict and restores state
# ============================================================
printf ' -> perform-rebase aborts on conflict and restores state\n'

REPO2="${TEST_TMPDIR}/rebase-conflict"
create_conflict_scenario "${REPO2}"

before_head="$(cd "${REPO2}" && git rev-parse HEAD)"

# This should fail but leave repo in clean state
# The fixture creates feature branch that conflicts with main
if run_tool_expect_fail gitHex.performRebase "${REPO2}" '{"onto": "main"}'; then
	# Verify repo is not in rebase state
	if [ -d "${REPO2}/.git/rebase-merge" ] || [ -d "${REPO2}/.git/rebase-apply" ]; then
		test_fail "repo should not be in rebase state after abort"
	fi
	
	# Verify HEAD is restored
	after_head="$(cd "${REPO2}" && git rev-parse HEAD)"
	assert_eq "${before_head}" "${after_head}" "HEAD should be restored after abort"
	
	test_pass "perform-rebase aborts on conflict and restores state"
else
	test_fail "should fail on conflict"
fi

# ============================================================
# TEST: perform-rebase fails on dirty working directory
# ============================================================
printf ' -> perform-rebase fails on dirty working directory\n'

REPO3="${TEST_TMPDIR}/rebase-dirty"
create_test_repo "${REPO3}" 3

# Make working directory dirty
echo "uncommitted" > "${REPO3}/dirty.txt"
(cd "${REPO3}" && git add dirty.txt)

if run_tool_expect_fail gitHex.performRebase "${REPO3}" '{"onto": "HEAD~1"}'; then
	test_pass "perform-rebase fails on dirty working directory"
else
	test_fail "should fail on dirty working directory"
fi

# ============================================================
# TEST: perform-rebase with autosquash
# ============================================================
printf ' -> perform-rebase with autosquash squashes fixup commits\n'

REPO4="${TEST_TMPDIR}/rebase-autosquash"
create_fixup_scenario "${REPO4}"

before_count="$(cd "${REPO4}" && git rev-list --count HEAD)"
assert_eq "4" "${before_count}" "should start with 4 commits"

result="$(run_tool gitHex.performRebase "${REPO4}" '{"onto": "HEAD~3", "autosquash": true}' 60)"

assert_json_field "${result}" '.success' "true" "rebase should succeed"

# After autosquash, the fixup commit should be squashed
after_count="$(cd "${REPO4}" && git rev-list --count HEAD)"
# Original: 4 commits (Initial, Add feature, fixup!, Add another)
# After autosquash: 3 commits (Initial, Add feature [squashed], Add another)
assert_eq "3" "${after_count}" "fixup commit should be squashed (4 -> 3 commits)"

test_pass "perform-rebase with autosquash works"

# ============================================================
# TEST: perform-rebase fails on empty repo
# ============================================================
printf ' -> perform-rebase fails on empty repo\n'

REPO5="${TEST_TMPDIR}/rebase-empty"
mkdir -p "${REPO5}"
(cd "${REPO5}" && git init --initial-branch=main >/dev/null 2>&1 && git config user.email "test@example.com" && git config user.name "Test" && git config commit.gpgsign false)

if run_tool_expect_fail gitHex.performRebase "${REPO5}" '{"onto": "HEAD~1"}'; then
	test_pass "perform-rebase fails on empty repo"
else
	test_fail "should fail on empty repo"
fi

echo ""
echo "All gitHex.performRebase tests passed!"
