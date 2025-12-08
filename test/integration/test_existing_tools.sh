#!/usr/bin/env bash
# Validation tests for existing tools (createFixup, amendLastCommit)
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

echo "=== Existing Tool Validation Tests ==="

# FIX-01: No staged changes -> fail
printf ' -> FIX-01 createFixup without staged changes fails\n'
REPO_FIX_FAIL="${TEST_TMPDIR}/create-fixup-fail"
create_test_repo "${REPO_FIX_FAIL}" 1
if run_tool_expect_fail git-hex-createFixup "${REPO_FIX_FAIL}" '{"commit": "HEAD"}'; then
	test_pass "createFixup fails without staged changes"
else
	test_fail "createFixup should fail with no staged changes"
fi

# FIX-02: With staged changes -> success
printf ' -> FIX-02 createFixup with staged changes succeeds\n'
REPO_FIX_OK="${TEST_TMPDIR}/create-fixup-ok"
create_staged_changes_repo "${REPO_FIX_OK}"
target_commit="$(cd "${REPO_FIX_OK}" && git rev-parse HEAD)"
result_fix="$(run_tool git-hex-createFixup "${REPO_FIX_OK}" "{\"commit\": \"${target_commit}\"}")"
assert_json_field "${result_fix}" '.success' "true" "createFixup should succeed with staged changes"
test_pass "createFixup succeeds with staged changes"

# AMD-01: Nothing to amend -> fail
printf ' -> AMD-01 amendLastCommit with nothing to amend fails\n'
REPO_AMD_FAIL="${TEST_TMPDIR}/amend-fail"
create_test_repo "${REPO_AMD_FAIL}" 1
if run_tool_expect_fail git-hex-amendLastCommit "${REPO_AMD_FAIL}" '{}'; then
	test_pass "amendLastCommit fails with nothing to amend"
else
	test_fail "amendLastCommit should fail when no changes or message"
fi

# AMD-02: Staged changes only -> success
printf ' -> AMD-02 amendLastCommit with staged changes succeeds\n'
REPO_AMD_STAGE="${TEST_TMPDIR}/amend-stage"
create_staged_changes_repo "${REPO_AMD_STAGE}"
result_amend_stage="$(run_tool git-hex-amendLastCommit "${REPO_AMD_STAGE}" '{}')"
assert_json_field "${result_amend_stage}" '.success' "true" "amendLastCommit should succeed with staged changes"
test_pass "amendLastCommit amends staged changes"

# AMD-03: Message only -> success
printf ' -> AMD-03 amendLastCommit with message only succeeds\n'
REPO_AMD_MSG="${TEST_TMPDIR}/amend-message"
create_test_repo "${REPO_AMD_MSG}" 1
result_amend_msg="$(run_tool git-hex-amendLastCommit "${REPO_AMD_MSG}" '{"message": "New message"}')"
assert_json_field "${result_amend_msg}" '.success' "true" "amendLastCommit should succeed with new message"
latest_msg="$(cd "${REPO_AMD_MSG}" && git log -1 --format='%s')"
assert_eq "New message" "${latest_msg}" "commit message should be updated"
test_pass "amendLastCommit updates message"

# AMD-04: Staged changes and message -> success
printf ' -> AMD-04 amendLastCommit with staged changes and message succeeds\n'
REPO_AMD_BOTH="${TEST_TMPDIR}/amend-both"
create_staged_changes_repo "${REPO_AMD_BOTH}"
result_amend_both="$(run_tool git-hex-amendLastCommit "${REPO_AMD_BOTH}" '{"message": "Both"}')"
assert_json_field "${result_amend_both}" '.success' "true" "amendLastCommit should succeed with staged changes and message"
latest_msg="$(cd "${REPO_AMD_BOTH}" && git log -1 --format='%s')"
assert_eq "Both" "${latest_msg}" "commit message should update"
test_pass "amendLastCommit handles staged + message"

echo ""
echo "Existing tool validation tests completed"
