#!/usr/bin/env bash
# Integration tests for gitHex.undoLast
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../common/env.sh"
. "${SCRIPT_DIR}/../common/assert.sh"
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
result="$(run_tool gitHex.performRebase "${REPO3}" '{"onto": "main"}' 60)"
assert_json_field "${result}" '.success' "true" "rebase should succeed"

rebased_head="$(cd "${REPO3}" && git rev-parse HEAD)"
assert_ne "${original_head}" "${rebased_head}" "HEAD should change after rebase"

# Now undo
result="$(run_tool gitHex.undoLast "${REPO3}" '{}')"
assert_json_field "${result}" '.success' "true" "undo should succeed"
assert_json_field "${result}" '.undoneOperation' "performRebase" "should report correct operation"

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
	
	echo "base" > base.txt
	git add base.txt && git commit -m "Base commit" >/dev/null
	
	git checkout -b source >/dev/null 2>&1
	echo "cherry" > cherry.txt
	git add cherry.txt && git commit -m "Cherry commit" >/dev/null
	cherry_hash="$(git rev-parse HEAD)"
	
	git checkout main >/dev/null 2>&1
	
	echo "${cherry_hash}" > /tmp/cherry_hash_undo_$$
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
echo "dirty" > "${REPO6}/dirty.txt"
(cd "${REPO6}" && git add dirty.txt)

if run_tool_expect_fail gitHex.undoLast "${REPO6}" '{}'; then
	test_pass "undo-last fails on dirty working directory"
else
	test_fail "should fail on dirty working directory"
fi

echo ""
echo "All gitHex.undoLast tests passed!"

