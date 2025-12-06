#!/usr/bin/env bash
# Integration tests for gitHex.createFixup
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../common/env.sh"
. "${SCRIPT_DIR}/../common/assert.sh"
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_verify_framework
test_create_tmpdir

echo "=== Testing gitHex.createFixup ==="

# ============================================================
# TEST: create-fixup creates fixup commit
# ============================================================
printf ' -> create-fixup creates fixup commit for target\n'

REPO="${TEST_TMPDIR}/fixup-basic"
create_staged_changes_repo "${REPO}"

target_hash="$(cd "${REPO}" && git rev-parse HEAD)"

result="$(run_tool gitHex.createFixup "${REPO}" "{\"commit\": \"${target_hash}\"}")"

assert_json_field "${result}" '.success' "true" "fixup should succeed"
assert_json_field "${result}" '.targetCommit' "${target_hash}" "target commit should match"

# Verify commit message starts with fixup!
fixup_message="$(echo "${result}" | jq -r '.message')"
assert_contains "${fixup_message}" "fixup!" "message should start with fixup!"

test_pass "create-fixup creates fixup commit"

# ============================================================
# TEST: create-fixup fails without staged changes
# ============================================================
printf ' -> create-fixup fails without staged changes\n'

REPO2="${TEST_TMPDIR}/fixup-no-staged"
create_test_repo "${REPO2}" 2

target_hash="$(cd "${REPO2}" && git rev-parse HEAD~1)"

if run_tool_expect_fail gitHex.createFixup "${REPO2}" "{\"commit\": \"${target_hash}\"}"; then
	test_pass "create-fixup fails without staged changes"
else
	test_fail "should fail without staged changes"
fi

# ============================================================
# TEST: create-fixup with custom message
# ============================================================
printf ' -> create-fixup with custom message appends it\n'

REPO3="${TEST_TMPDIR}/fixup-message"
create_staged_changes_repo "${REPO3}"

target_hash="$(cd "${REPO3}" && git rev-parse HEAD)"

result="$(run_tool gitHex.createFixup "${REPO3}" "{\"commit\": \"${target_hash}\", \"message\": \"Additional context\"}")"

assert_json_field "${result}" '.success' "true" "fixup should succeed"

# Verify the commit body contains the extra message
full_message="$(cd "${REPO3}" && git log -1 --format='%B' HEAD)"
assert_contains "${full_message}" "Additional context" "commit body should contain extra message"

test_pass "create-fixup with custom message works"

# ============================================================
# TEST: create-fixup fails on invalid commit ref
# ============================================================
printf ' -> create-fixup fails on invalid commit ref\n'

REPO4="${TEST_TMPDIR}/fixup-invalid"
create_staged_changes_repo "${REPO4}"

if run_tool_expect_fail gitHex.createFixup "${REPO4}" '{"commit": "nonexistent123"}'; then
	test_pass "create-fixup fails on invalid commit ref"
else
	test_fail "should fail on invalid commit ref"
fi

echo ""
echo "All gitHex.createFixup tests passed!"
