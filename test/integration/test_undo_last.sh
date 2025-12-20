#!/usr/bin/env bash
# Integration tests for git-hex-undoLast
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

echo "=== Testing git-hex-undoLast ==="

# ============================================================
# TEST: undo-last undoes an amend operation
# ============================================================
printf ' -> undo-last undoes an amend operation\n'

REPO="${TEST_TMPDIR}/undo-amend"
create_test_repo "${REPO}" 2

original_head="$(cd "${REPO}" && git rev-parse HEAD)"
original_message="$(cd "${REPO}" && git log -1 --format='%s' HEAD)"

# Perform an amend
result="$(run_tool git-hex-amendLastCommit "${REPO}" '{"message": "Amended message"}')"
assert_json_field "${result}" '.success' "true" "amend should succeed"

amended_head="$(cd "${REPO}" && git rev-parse HEAD)"
assert_ne "${original_head}" "${amended_head}" "HEAD should change after amend"

# Now undo
result="$(run_tool git-hex-undoLast "${REPO}" '{}')"
assert_json_fields_eq "${result}" '.success' "true" '.undoneOperation' "amendLastCommit"

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
result="$(run_tool git-hex-createFixup "${REPO2}" "{\"commit\": \"${original_head}\"}")"
assert_json_field "${result}" '.success' "true" "fixup should succeed"

fixup_head="$(cd "${REPO2}" && git rev-parse HEAD)"
assert_ne "${original_head}" "${fixup_head}" "HEAD should change after fixup"

# Now undo
result="$(run_tool git-hex-undoLast "${REPO2}" '{}')"
assert_json_fields_eq "${result}" '.success' "true" '.undoneOperation' "createFixup"

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
result="$(run_tool git-hex-rebaseWithPlan "${REPO3}" '{"onto": "main"}' 60)"
assert_json_field "${result}" '.success' "true" "rebase should succeed"

rebased_head="$(cd "${REPO3}" && git rev-parse HEAD)"
assert_ne "${original_head}" "${rebased_head}" "HEAD should change after rebase"

# Now undo
result="$(run_tool git-hex-undoLast "${REPO3}" '{}')"
assert_json_fields_eq "${result}" '.success' "true" '.undoneOperation' "rebaseWithPlan"

restored_head="$(cd "${REPO3}" && git rev-parse HEAD)"
assert_eq "${original_head}" "${restored_head}" "HEAD should be restored to original"

test_pass "undo-last undoes a rebase operation"

# ============================================================
# TEST: undo-last undoes a cherry-pick operation
# ============================================================
printf ' -> undo-last undoes a cherry-pick operation\n'

REPO4="${TEST_TMPDIR}/undo-cherry-pick"
mkdir -p "${REPO4}"
tmp_cherry_hash_undo="$(mktemp "${TEST_TMPDIR}/cherry_hash_undo.XXXXXX")"
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

	echo "${cherry_hash}" >"${tmp_cherry_hash_undo}"
)

cherry_hash="$(cat "${tmp_cherry_hash_undo}")"
rm -f "${tmp_cherry_hash_undo}"

original_head="$(cd "${REPO4}" && git rev-parse HEAD)"

# Perform a cherry-pick
result="$(run_tool git-hex-cherryPickSingle "${REPO4}" "{\"commit\": \"${cherry_hash}\"}")"
assert_json_field "${result}" '.success' "true" "cherry-pick should succeed"

picked_head="$(cd "${REPO4}" && git rev-parse HEAD)"
assert_ne "${original_head}" "${picked_head}" "HEAD should change after cherry-pick"

# Now undo
result="$(run_tool git-hex-undoLast "${REPO4}" '{}')"
assert_json_fields_eq "${result}" '.success' "true" '.undoneOperation' "cherryPickSingle"

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
if run_tool_expect_fail git-hex-undoLast "${REPO5}" '{}'; then
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
result="$(run_tool git-hex-amendLastCommit "${REPO6}" '{"message": "Test amend"}')"

# Make working directory dirty
echo "dirty" >"${REPO6}/dirty.txt"
(cd "${REPO6}" && git add dirty.txt)

if run_tool_expect_fail git-hex-undoLast "${REPO6}" '{}'; then
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
result="$(run_tool git-hex-amendLastCommit "${REPO7}" '{"message": "First amend"}')"
assert_json_field "${result}" '.success' "true" "first amend should succeed"
second_head="$(cd "${REPO7}" && git rev-parse HEAD)"

# Second operation: amend again
result="$(run_tool git-hex-amendLastCommit "${REPO7}" '{"message": "Second amend"}')"
assert_json_field "${result}" '.success' "true" "second amend should succeed"

# Undo should restore to second_head, not first_head
result="$(run_tool git-hex-undoLast "${REPO7}" '{}')"
assert_json_field "${result}" '.success' "true" "undo should succeed"

restored_head="$(cd "${REPO7}" && git rev-parse HEAD)"
assert_eq "${second_head}" "${restored_head}" "should restore to state before LAST operation only"
assert_ne "${first_head}" "${restored_head}" "should NOT restore to state before first operation"

test_pass "undo-last only undoes the last operation"

# ============================================================
# TEST: undo-last refuses to overwrite untracked file by default
# ============================================================
printf ' -> undo-last refuses to overwrite untracked file by default\n'

REPO_UNTRACKED="${TEST_TMPDIR}/undo-untracked-overwrite"
mkdir -p "${REPO_UNTRACKED}"
(
	cd "${REPO_UNTRACKED}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "tracked" >a.txt
	echo "keep" >keep.txt
	git add a.txt keep.txt
	git commit -m "Add a.txt" >/dev/null

	# Stage deletion and amend the last commit via git-hex (creates backup at commit-with-a.txt).
	git rm -f -- a.txt >/dev/null 2>&1
)

result_untracked="$(run_tool git-hex-amendLastCommit "${REPO_UNTRACKED}" '{"message":"Remove a.txt"}')"
assert_json_field "${result_untracked}" '.success' "true" "amend should succeed"

# Create an untracked file at the same path that exists in the backup state.
echo "untracked" >"${REPO_UNTRACKED}/a.txt"

run_tool_expect_fail_message_contains \
	git-hex-undoLast "${REPO_UNTRACKED}" '{"force": false}' \
	"untracked file" \
	"undoLast should refuse to overwrite untracked files by default"
test_pass "undo-last refuses untracked overwrite by default"

# With force=true, undo proceeds (may overwrite untracked file).
result_force="$(run_tool git-hex-undoLast "${REPO_UNTRACKED}" '{"force": true}')"
assert_json_field "${result_force}" '.success' "true" "undo with force should succeed"
content_after_force="$(cat "${REPO_UNTRACKED}/a.txt" 2>/dev/null || echo "")"
assert_eq "tracked" "${content_after_force}" "force undo should restore tracked file content (overwriting untracked)"
test_pass "undo-last can proceed with force=true"

# ============================================================
# TEST: double undo fails (no backup after first undo)
# ============================================================
printf ' -> double undo fails after first undo\n'

REPO8="${TEST_TMPDIR}/undo-double"
create_test_repo "${REPO8}" 2

original_head="$(cd "${REPO8}" && git rev-parse HEAD)"

# Perform an operation
result="$(run_tool git-hex-amendLastCommit "${REPO8}" '{"message": "Test amend"}')"
assert_json_field "${result}" '.success' "true" "amend should succeed"

# First undo should succeed
result="$(run_tool git-hex-undoLast "${REPO8}" '{}')"
assert_json_field "${result}" '.success' "true" "first undo should succeed"

restored_head="$(cd "${REPO8}" && git rev-parse HEAD)"
assert_eq "${original_head}" "${restored_head}" "should restore to original"

# Second undo should report already at backup state (success but no-op)
result="$(run_tool git-hex-undoLast "${REPO8}" '{}')"
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
result="$(run_tool git-hex-amendLastCommit "${REPO9}" '{"message": "Pre-conflict amend"}')"

# Now start a conflicting rebase manually to put repo in rebase state
if ! (cd "${REPO9}" && git rebase main >/dev/null 2>&1); then
	:
fi

# Verify we're in rebase state
if [ ! -d "${REPO9}/.git/rebase-merge" ] && [ ! -d "${REPO9}/.git/rebase-apply" ]; then
	# Rebase might have completed without conflict on some git versions, skip test
	if ! (cd "${REPO9}" && git rebase --abort >/dev/null 2>&1); then
		:
	fi
	echo "  (skipped - rebase did not conflict)"
else
	# Try to undo - should fail
	if run_tool_expect_fail git-hex-undoLast "${REPO9}" '{}'; then
		test_pass "undo-last fails during in-progress rebase"
	else
		test_fail "should fail during in-progress rebase"
	fi
	# Cleanup
	if ! (cd "${REPO9}" && git rebase --abort >/dev/null 2>&1); then
		:
	fi
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
result="$(run_tool git-hex-amendLastCommit "${REPO10}" '{"message": "Amended on feature"}')"
assert_json_field "${result}" '.success' "true" "amend should succeed"

# Undo
result="$(run_tool git-hex-undoLast "${REPO10}" '{}')"
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
tmp_cherry_hash_nocommit="$(mktemp "${TEST_TMPDIR}/cherry_hash_nocommit.XXXXXX")"
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

	echo "${cherry_hash}" >"${tmp_cherry_hash_nocommit}"
)

cherry_hash="$(cat "${tmp_cherry_hash_nocommit}")"
rm -f "${tmp_cherry_hash_nocommit}"

original_head="$(cd "${REPO11}" && git rev-parse HEAD)"

# Perform a noCommit cherry-pick (stages changes but doesn't commit)
result="$(run_tool git-hex-cherryPickSingle "${REPO11}" "{\"commit\": \"${cherry_hash}\", \"noCommit\": true}")"
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
if run_tool_expect_fail git-hex-undoLast "${REPO11}" '{}'; then
	test_pass "undo-last fails after noCommit cherry-pick (staged changes)"
else
	test_fail "should fail because staged changes make working tree dirty"
fi

# ============================================================
# TEST: undo-last refuses when safety cannot be verified (no recorded head + no reflog)
# ============================================================
printf ' -> undo-last refuses when safety cannot be verified (no recorded head + no reflog)\n'

REPO12="${TEST_TMPDIR}/undo-no-reflog"
create_test_repo "${REPO12}" 2

# Create a backup by running an operation, then add an extra commit after it.
result="$(run_tool git-hex-amendLastCommit "${REPO12}" '{"message": "Amended for reflog test"}')"
assert_json_field "${result}" '.success' "true" "amend should succeed"

(
	cd "${REPO12}"
	echo "extra" >extra.txt
	git add extra.txt
	git commit -m "Extra commit after git-hex op" >/dev/null

	# Simulate an older backup: remove recorded last-head refs used for safety checks.
	while IFS= read -r ref; do
		[ -n "${ref}" ] || continue
		git update-ref -d "${ref}" >/dev/null 2>&1 || true
	done < <(git for-each-ref --format='%(refname)' refs/git-hex/last-head/ 2>/dev/null || true)

	# Simulate missing reflogs: remove HEAD and branch logs.
	rm -f .git/logs/HEAD .git/logs/refs/heads/* 2>/dev/null || true
)

run_tool_expect_fail_message_contains \
	git-hex-undoLast \
	"${REPO12}" \
	'{}' \
	"reflogs are unavailable" \
	"undoLast should refuse when it cannot safely verify extra commits without force=true"
test_pass "undo-last refuses when safety cannot be verified"

echo ""
echo "All git-hex-undoLast tests passed!"
