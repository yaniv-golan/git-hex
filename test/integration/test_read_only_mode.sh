#!/usr/bin/env bash
# Integration tests for GIT_HEX_READ_ONLY mode
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=../common/env.sh disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"
# shellcheck source=../common/git_fixtures.sh disable=SC1091
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_verify_framework
test_create_tmpdir

echo "=== Testing GIT_HEX_READ_ONLY mode ==="

# ============================================================
# TEST: read-only mode allows getRebasePlan
# ============================================================
printf ' -> read-only mode allows getRebasePlan\n'

REPO="${TEST_TMPDIR}/readonly-allow"
create_test_repo "${REPO}" 3

# Run with read-only mode enabled
export GIT_HEX_READ_ONLY=1
result="$(run_tool git-hex-getRebasePlan "${REPO}" '{"count": 3}')"
unset GIT_HEX_READ_ONLY

assert_json_field "${result}" '.success' "true" "getRebasePlan should succeed in read-only mode"

test_pass "read-only mode allows getRebasePlan"

# ============================================================
# TEST: read-only mode blocks amendLastCommit
# ============================================================
printf ' -> read-only mode blocks amendLastCommit\n'

REPO2="${TEST_TMPDIR}/readonly-block-amend"
create_test_repo "${REPO2}" 2

export GIT_HEX_READ_ONLY=1
if run_tool_expect_fail git-hex-amendLastCommit "${REPO2}" '{"message": "test"}'; then
	test_pass "read-only mode blocks amendLastCommit"
else
	test_fail "amendLastCommit should fail in read-only mode"
fi
unset GIT_HEX_READ_ONLY

# ============================================================
# TEST: read-only mode blocks createFixup
# ============================================================
printf ' -> read-only mode blocks createFixup\n'

REPO3="${TEST_TMPDIR}/readonly-block-fixup"
create_staged_changes_repo "${REPO3}"
target_hash="$(cd "${REPO3}" && git rev-parse HEAD)"

export GIT_HEX_READ_ONLY=1
if run_tool_expect_fail git-hex-createFixup "${REPO3}" "{\"commit\": \"${target_hash}\"}"; then
	test_pass "read-only mode blocks createFixup"
else
	test_fail "createFixup should fail in read-only mode"
fi
unset GIT_HEX_READ_ONLY

# ============================================================
# TEST: read-only mode blocks rebaseWithPlan
# ============================================================
printf ' -> read-only mode blocks rebaseWithPlan\n'

REPO4="${TEST_TMPDIR}/readonly-block-rebase"
create_branch_scenario "${REPO4}"

export GIT_HEX_READ_ONLY=1
if run_tool_expect_fail git-hex-rebaseWithPlan "${REPO4}" '{"onto": "main"}'; then
	test_pass "read-only mode blocks rebaseWithPlan"
else
	test_fail "rebaseWithPlan should fail in read-only mode"
fi
unset GIT_HEX_READ_ONLY

# ============================================================
# TEST: read-only mode blocks cherryPickSingle
# ============================================================
printf ' -> read-only mode blocks cherryPickSingle\n'

REPO5="${TEST_TMPDIR}/readonly-block-cherry"
mkdir -p "${REPO5}"
(
	cd "${REPO5}"
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

	echo "${cherry_hash}" >/tmp/cherry_hash_readonly_$$
)

cherry_hash="$(cat /tmp/cherry_hash_readonly_$$)"
rm -f /tmp/cherry_hash_readonly_$$

export GIT_HEX_READ_ONLY=1
if run_tool_expect_fail git-hex-cherryPickSingle "${REPO5}" "{\"commit\": \"${cherry_hash}\"}"; then
	test_pass "read-only mode blocks cherryPickSingle"
else
	test_fail "cherryPickSingle should fail in read-only mode"
fi
unset GIT_HEX_READ_ONLY

# ============================================================
# TEST: read-only mode blocks undoLast
# ============================================================
printf ' -> read-only mode blocks undoLast\n'

REPO6="${TEST_TMPDIR}/readonly-block-undo"
create_test_repo "${REPO6}" 2

# First, create a backup by running an operation (without read-only)
result="$(run_tool git-hex-amendLastCommit "${REPO6}" '{"message": "Create backup"}')"

# Now try to undo in read-only mode
export GIT_HEX_READ_ONLY=1
if run_tool_expect_fail git-hex-undoLast "${REPO6}" '{}'; then
	test_pass "read-only mode blocks undoLast"
else
	test_fail "undoLast should fail in read-only mode"
fi
unset GIT_HEX_READ_ONLY

# ============================================================
# TEST: tools work normally when read-only mode is off
# ============================================================
printf ' -> tools work normally when read-only mode is off\n'

REPO7="${TEST_TMPDIR}/readonly-off"
create_test_repo "${REPO7}" 2

# Explicitly unset to ensure it's off
unset GIT_HEX_READ_ONLY 2>/dev/null || true

result="$(run_tool git-hex-amendLastCommit "${REPO7}" '{"message": "Normal operation"}')"
assert_json_field "${result}" '.success' "true" "amendLastCommit should work when read-only is off"

test_pass "tools work normally when read-only mode is off"

echo ""
echo "All GIT_HEX_READ_ONLY mode tests passed!"
