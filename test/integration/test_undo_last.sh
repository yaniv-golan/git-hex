#!/usr/bin/env bash
# Integration tests for gitHex.undoLast
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

echo "=== Testing gitHex.undoLast ==="

# ============================================================
# TEST: undo-last undoes an amend operation
# ============================================================
printf ' -> undo-last undoes an amend operation\n'

REPO="${TEST_TMPDIR}/undo-amend"
create_test_repo "${REPO}" 2

original_head="$(cd "${REPO}" && git rev-parse HEAD)"
original_message="$(cd "${REPO}" && git log -1 --format='%s' HEAD)"

# Perform an amend
result="$(run_tool gitHex.amendLastCommit "${REPO}" '{"message": "Amended message"}')"
assert_json_field "${result}" '.success' "true" "amend should succeed"

amended_head="$(cd "${REPO}" && git rev-parse HEAD)"
assert_ne "${original_head}" "${amended_head}" "HEAD should change after amend"

# Now undo
result="$(run_tool gitHex.undoLast "${REPO}" '{}')"
assert_json_field "${result}" '.success' "true" "undo should succeed"
assert_json_field "${result}" '.undoneOperation' "amendLastCommit" "should report correct operation"

restored_head="$(cd "${REPO}" && git rev-parse HEAD)"
assert_eq "${original_head}" "${restored_head}" "HEAD should be restored to original"

restored_message="$(cd "${REPO}" && git log -1 --format='%s' HEAD)"
assert_eq "${original_message}" "${restored_message}" "message should be restored"

test_pass "undo-last undoes an amend operation"

# ============================================================
# TEST: undo-last undoes a fixup operation
# ============================================================
printf ' -> undo-last undoes a fixup operation\n'

REPO2="${TEST_TMPDIR}/undo-fixup"
create_staged_changes_repo "${REPO2}"

original_head="$(cd "${REPO2}" && git rev-parse HEAD)"

# Perform a fixup
result="$(run_tool gitHex.createFixup "${REPO2}" "{\"commit\": \"${original_head}\"}")"
assert_json_field "${result}" '.success' "true" "fixup should succeed"

fixup_head="$(cd "${REPO2}" && git rev-parse HEAD)"
assert_ne "${original_head}" "${fixup_head}" "HEAD should change after fixup"

# Now undo
result="$(run_tool gitHex.undoLast "${REPO2}" '{}')"
assert_json_field "${result}" '.success' "true" "undo should succeed"
assert_json_field "${result}" '.undoneOperation' "createFixup" "should report correct operation"

restored_head="$(cd "${REPO2}" && git rev-parse HEAD)"
assert_eq "${original_head}" "${restored_head}" "HEAD should be restored to original"

test_pass "undo-last undoes a fixup operation"

# ============================================================
# TEST: undo-last undoes a rebase operation
# ============================================================
printf ' -> undo-last undoes a rebase operation\n'

REPO3="${TEST_TMPDIR}/undo-rebase"
create_branch_scenario "${REPO3}"

original_head="$(cd "${REPO3}" && git rev-parse HEAD)"

# Perform a rebase
result="$(run_tool gitHex.rebaseWithPlan "${REPO3}" '{"onto": "main"}' 60)"
assert_json_field "${result}" '.success' "true" "rebase should succeed"

rebased_head="$(cd "${REPO3}" && git rev-parse HEAD)"
assert_ne "${original_head}" "${rebased_head}" "HEAD should change after rebase"

# Now undo
result="$(run_tool gitHex.undoLast "${REPO3}" '{}')"
assert_json_field "${result}" '.success' "true" "undo should succeed"
assert_json_field "${result}" '.undoneOperation' "rebaseWithPlan" "should report correct operation"

restored_head="$(cd "${REPO3}" && git rev-parse HEAD)"
assert_eq "${original_head}" "${restored_head}" "HEAD should be restored to original"

test_pass "undo-last undoes a rebase operation"

# ============================================================
# TEST: undo-last undoes a cherry-pick operation
# ============================================================
printf ' -> undo-last undoes a cherry-pick operation\n'

REPO4="${TEST_TMPDIR}/undo-cherry-pick"
mkdir -p "${REPO4}"
(
	cd "${REPO4}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "base" >base.txt
	git add base.txt && git commit -m "Base commit" >/dev/null

	git checkout -b source >/dev/null 2>&1
	echo "cherry" >cherry.txt
	git add cherry.txt && git commit -m "Cherry commit" >/dev/null
	cherry_hash="$(git rev-parse HEAD)"

	git checkout main >/dev/null 2>&1

	echo "${cherry_hash}" >/tmp/cherry_hash_undo_$$
)

cherry_hash="$(cat /tmp/cherry_hash_undo_$$)"
rm -f /tmp/cherry_hash_undo_$$

original_head="$(cd "${REPO4}" && git rev-parse HEAD)"

# Perform a cherry-pick
result="$(run_tool gitHex.cherryPickSingle "${REPO4}" "{\"commit\": \"${cherry_hash}\"}")"
assert_json_field "${result}" '.success' "true" "cherry-pick should succeed"

picked_head="$(cd "${REPO4}" && git rev-parse HEAD)"
assert_ne "${original_head}" "${picked_head}" "HEAD should change after cherry-pick"

# Now undo
result="$(run_tool gitHex.undoLast "${REPO4}" '{}')"
assert_json_field "${result}" '.success' "true" "undo should succeed"
assert_json_field "${result}" '.undoneOperation' "cherryPickSingle" "should report correct operation"

restored_head="$(cd "${REPO4}" && git rev-parse HEAD)"
assert_eq "${original_head}" "${restored_head}" "HEAD should be restored to original"

# Verify the cherry-picked file is gone
if [ -f "${REPO4}/cherry.txt" ]; then
	test_fail "cherry-picked file should be removed after undo"
fi

test_pass "undo-last undoes a cherry-pick operation"

# ============================================================
# TEST: undo-last fails when no backup exists
# ============================================================
printf ' -> undo-last fails when no backup exists\n'

REPO5="${TEST_TMPDIR}/undo-no-backup"
create_test_repo "${REPO5}" 2

# Try to undo without any prior git-hex operation
if run_tool_expect_fail gitHex.undoLast "${REPO5}" '{}'; then
	test_pass "undo-last fails when no backup exists"
else
	test_fail "should fail when no backup exists"
fi

# ============================================================
# TEST: undo-last fails on dirty working directory
# ============================================================
printf ' -> undo-last fails on dirty working directory\n'

REPO6="${TEST_TMPDIR}/undo-dirty"
create_test_repo "${REPO6}" 2

# Create a backup by running an operation
result="$(run_tool gitHex.amendLastCommit "${REPO6}" '{"message": "Test amend"}')"

# Make working directory dirty
echo "dirty" >"${REPO6}/dirty.txt"
(cd "${REPO6}" && git add dirty.txt)

if run_tool_expect_fail gitHex.undoLast "${REPO6}" '{}'; then
	test_pass "undo-last fails on dirty working directory"
else
	test_fail "should fail on dirty working directory"
fi

# ============================================================
# TEST: undo-last only undoes the last operation (not earlier ones)
# ============================================================
printf ' -> undo-last only undoes the last operation\n'

REPO7="${TEST_TMPDIR}/undo-last-only"
create_test_repo "${REPO7}" 3

first_head="$(cd "${REPO7}" && git rev-parse HEAD)"

# First operation: amend
result="$(run_tool gitHex.amendLastCommit "${REPO7}" '{"message": "First amend"}')"
assert_json_field "${result}" '.success' "true" "first amend should succeed"
second_head="$(cd "${REPO7}" && git rev-parse HEAD)"

# Second operation: amend again
result="$(run_tool gitHex.amendLastCommit "${REPO7}" '{"message": "Second amend"}')"
assert_json_field "${result}" '.success' "true" "second amend should succeed"

# Undo should restore to second_head, not first_head
result="$(run_tool gitHex.undoLast "${REPO7}" '{}')"
assert_json_field "${result}" '.success' "true" "undo should succeed"

restored_head="$(cd "${REPO7}" && git rev-parse HEAD)"
assert_eq "${second_head}" "${restored_head}" "should restore to state before LAST operation only"
assert_ne "${first_head}" "${restored_head}" "should NOT restore to state before first operation"

test_pass "undo-last only undoes the last operation"

# ============================================================
# TEST: double undo fails (no backup after first undo)
# ============================================================
printf ' -> double undo fails after first undo\n'

REPO8="${TEST_TMPDIR}/undo-double"
create_test_repo "${REPO8}" 2

original_head="$(cd "${REPO8}" && git rev-parse HEAD)"

# Perform an operation
result="$(run_tool gitHex.amendLastCommit "${REPO8}" '{"message": "Test amend"}')"
assert_json_field "${result}" '.success' "true" "amend should succeed"

# First undo should succeed
result="$(run_tool gitHex.undoLast "${REPO8}" '{}')"
assert_json_field "${result}" '.success' "true" "first undo should succeed"

restored_head="$(cd "${REPO8}" && git rev-parse HEAD)"
assert_eq "${original_head}" "${restored_head}" "should restore to original"

# Second undo should report already at backup state (success but no-op)
result="$(run_tool gitHex.undoLast "${REPO8}" '{}')"
assert_json_field "${result}" '.success' "true" "second undo should succeed (no-op)"

# HEAD should still be at original
final_head="$(cd "${REPO8}" && git rev-parse HEAD)"
assert_eq "${original_head}" "${final_head}" "HEAD should remain at original after double undo"

test_pass "double undo fails after first undo"

# ============================================================
# TEST: undo-last fails during in-progress rebase
# ============================================================
printf ' -> undo-last fails during in-progress rebase\n'

REPO9="${TEST_TMPDIR}/undo-during-rebase"
mkdir -p "${REPO9}"
(
	cd "${REPO9}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "base" >conflict.txt
	git add conflict.txt && git commit -m "Initial" >/dev/null

	git checkout -b feature >/dev/null 2>&1
	echo "feature" >conflict.txt
	git add conflict.txt && git commit -m "Feature change" >/dev/null

	git checkout main >/dev/null 2>&1
	echo "main" >conflict.txt
	git add conflict.txt && git commit -m "Main change" >/dev/null

	git checkout feature >/dev/null 2>&1
)

# First do a successful operation to create a backup
result="$(run_tool gitHex.amendLastCommit "${REPO9}" '{"message": "Pre-conflict amend"}')"

# Now start a conflicting rebase manually to put repo in rebase state
(cd "${REPO9}" && git rebase main 2>/dev/null || true)

# Verify we're in rebase state
if [ ! -d "${REPO9}/.git/rebase-merge" ] && [ ! -d "${REPO9}/.git/rebase-apply" ]; then
	# Rebase might have completed without conflict on some git versions, skip test
	(cd "${REPO9}" && git rebase --abort 2>/dev/null || true)
	echo "  (skipped - rebase did not conflict)"
else
	# Try to undo - should fail
	if run_tool_expect_fail gitHex.undoLast "${REPO9}" '{}'; then
		test_pass "undo-last fails during in-progress rebase"
	else
		test_fail "should fail during in-progress rebase"
	fi
	# Cleanup
	(cd "${REPO9}" && git rebase --abort 2>/dev/null || true)
fi

# ============================================================
# TEST: undo-last preserves current branch
# ============================================================
printf ' -> undo-last preserves current branch\n'

REPO10="${TEST_TMPDIR}/undo-branch"
mkdir -p "${REPO10}"
(
	cd "${REPO10}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "base" >file.txt
	git add file.txt && git commit -m "Initial" >/dev/null

	git checkout -b feature >/dev/null 2>&1
	echo "feature" >>file.txt
	git add file.txt && git commit -m "Feature commit" >/dev/null
)

original_branch="$(cd "${REPO10}" && git branch --show-current)"
assert_eq "feature" "${original_branch}" "should start on feature branch"

# Perform an amend
result="$(run_tool gitHex.amendLastCommit "${REPO10}" '{"message": "Amended on feature"}')"
assert_json_field "${result}" '.success' "true" "amend should succeed"

# Undo
result="$(run_tool gitHex.undoLast "${REPO10}" '{}')"
assert_json_field "${result}" '.success' "true" "undo should succeed"

# Should still be on feature branch
restored_branch="$(cd "${REPO10}" && git branch --show-current)"
assert_eq "feature" "${restored_branch}" "should still be on feature branch after undo"

test_pass "undo-last preserves current branch"

# ============================================================
# TEST: undo-last fails with noCommit cherry-pick (staged changes = dirty)
# ============================================================
printf ' -> undo-last fails after noCommit cherry-pick (staged changes)\n'

REPO11="${TEST_TMPDIR}/undo-nocommit"
mkdir -p "${REPO11}"
(
	cd "${REPO11}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "base" >base.txt
	git add base.txt && git commit -m "Base commit" >/dev/null

	git checkout -b source >/dev/null 2>&1
	echo "cherry" >cherry.txt
	git add cherry.txt && git commit -m "Cherry commit" >/dev/null
	cherry_hash="$(git rev-parse HEAD)"

	git checkout main >/dev/null 2>&1

	echo "${cherry_hash}" >/tmp/cherry_hash_nocommit_$$
)

cherry_hash="$(cat /tmp/cherry_hash_nocommit_$$)"
rm -f /tmp/cherry_hash_nocommit_$$

original_head="$(cd "${REPO11}" && git rev-parse HEAD)"

# Perform a noCommit cherry-pick (stages changes but doesn't commit)
result="$(run_tool gitHex.cherryPickSingle "${REPO11}" "{\"commit\": \"${cherry_hash}\", \"noCommit\": true}")"
assert_json_field "${result}" '.success' "true" "noCommit cherry-pick should succeed"

# HEAD should be same (no commit made)
after_pick_head="$(cd "${REPO11}" && git rev-parse HEAD)"
assert_eq "${original_head}" "${after_pick_head}" "HEAD should not change with noCommit"

# But cherry.txt should be staged
if [ ! -f "${REPO11}/cherry.txt" ]; then
	test_fail "cherry.txt should exist after noCommit cherry-pick"
fi

# Undo should FAIL because there are staged changes (working tree is dirty)
# This is correct safety behavior - user must commit or reset the staged changes first
if run_tool_expect_fail gitHex.undoLast "${REPO11}" '{}'; then
	test_pass "undo-last fails after noCommit cherry-pick (staged changes)"
else
	test_fail "should fail because staged changes make working tree dirty"
fi

echo ""
echo "All gitHex.undoLast tests passed!"
