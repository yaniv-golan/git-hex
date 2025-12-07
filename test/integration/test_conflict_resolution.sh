#!/usr/bin/env bash
# Integration tests for conflict status and resolution tools
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

echo "=== Conflict Resolution Tests ==="

# CONF-01: No conflict returns inConflict=false
printf ' -> CONF-01 getConflictStatus on clean repo\n'
CLEAN_REPO="${TEST_TMPDIR}/conflict-clean"
create_test_repo "${CLEAN_REPO}" 2
status="$(run_tool gitHex.getConflictStatus "${CLEAN_REPO}" '{}')"
assert_json_field "${status}" '.inConflict' "false" "clean repo should not report conflicts"
test_pass "getConflictStatus reports clean state"

# Prepare common conflict scenario (rebase paused)
prepare_rebase_conflict()  {
	local repo="$1"
	create_conflict_scenario "${repo}"
	(cd "${repo}" && git rebase main >/dev/null 2>&1) || true
}

# CONF-02: Rebase conflict detected
printf ' -> CONF-02 rebase conflict detected\n'
REPO_REBASE="${TEST_TMPDIR}/conflict-rebase"
prepare_rebase_conflict "${REPO_REBASE}"
status="$(run_tool gitHex.getConflictStatus "${REPO_REBASE}" '{}')"
assert_json_field "${status}" '.inConflict' "true" "rebase should be paused with conflict"
assert_json_field "${status}" '.conflictType' "rebase" "conflictType should be rebase"
test_pass "rebase conflict detected"

# CONF-03: Cherry-pick conflict detected
printf ' -> CONF-03 cherry-pick conflict detected\n'
REPO_PICK="${TEST_TMPDIR}/conflict-cherry-pick"
create_paused_cherry_pick_scenario "${REPO_PICK}"
status="$(run_tool gitHex.getConflictStatus "${REPO_PICK}" '{}')"
assert_json_field "${status}" '.conflictType' "cherry-pick" "conflictType should be cherry-pick"
test_pass "cherry-pick conflict detected"

# CONF-04: Merge conflict detected
printf ' -> CONF-04 merge conflict detected\n'
REPO_MERGE="${TEST_TMPDIR}/conflict-merge"
create_paused_merge_scenario "${REPO_MERGE}"
status="$(run_tool gitHex.getConflictStatus "${REPO_MERGE}" '{}')"
assert_json_field "${status}" '.conflictType' "merge" "conflictType should be merge"
test_pass "merge conflict detected"

# CONF-05/20: includeContent true returns content for text file conflicts
printf ' -> CONF-20 includeContent returns text content\n'
REPO_CONTENT="${TEST_TMPDIR}/conflict-content"
prepare_rebase_conflict "${REPO_CONTENT}"
status="$(run_tool gitHex.getConflictStatus "${REPO_CONTENT}" '{"includeContent": true, "maxContentSize": 200}')"
assert_json_field "${status}" '.conflictingFiles[0].isBinary' "false" "text conflict should not be binary"
base_content="$(printf '%s' "${status}" | jq -r '.conflictingFiles[0].base')"
if [ -n "${base_content}" ]; then
	test_pass "includeContent returned base/ours/theirs"
else
	test_fail "includeContent should include file contents"
fi

# CONF-22: Binary file excluded from content
printf ' -> CONF-22 binary file treated as binary\n'
REPO_BINARY="${TEST_TMPDIR}/conflict-binary"
create_binary_conflict_scenario "${REPO_BINARY}"
(cd "${REPO_BINARY}" && git rebase main >/dev/null 2>&1) || true
status="$(run_tool gitHex.getConflictStatus "${REPO_BINARY}" '{"includeContent": true}')"
assert_json_field "${status}" '.conflictingFiles[0].isBinary' "true" "binary conflict should mark isBinary"
test_pass "binary conflict reported without content"

# CONF-23: Binary conflict with missing working copy does not emit content
printf ' -> CONF-23 binary conflict with missing working copy\n'
REPO_BINARY_DELETE="${TEST_TMPDIR}/conflict-binary-delete"
create_binary_delete_conflict_scenario "${REPO_BINARY_DELETE}"
(cd "${REPO_BINARY_DELETE}" && git rebase main >/dev/null 2>&1) || true
status_delete="$(run_tool gitHex.getConflictStatus "${REPO_BINARY_DELETE}" '{"includeContent": true}')"
assert_json_field "${status_delete}" '.conflictingFiles[0].isBinary' "true" "binary delete/modify conflict should mark isBinary"
base_val="$(printf '%s' "${status_delete}" | jq -r '.conflictingFiles[0].base?')"
if [ "${base_val}" = "null" ] || [ -z "${base_val}" ]; then
	test_pass "binary conflict without working file did not return blob contents"
else
	test_fail "binary conflict without working file should not include content"
fi

# RESV-01/partial: Resolve modified file then continue
printf ' -> RESV-01 resolve conflict and continueOperation\n'
REPO_RESOLVE="${TEST_TMPDIR}/conflict-resolve"
prepare_rebase_conflict "${REPO_RESOLVE}"
echo "resolved content" >"${REPO_RESOLVE}/conflict.txt"
res_result="$(run_tool gitHex.resolveConflict "${REPO_RESOLVE}" '{"file": "conflict.txt"}')"
assert_json_field "${res_result}" '.remainingConflicts' "0" "all conflicts should be resolved"
cont_result="$(run_tool gitHex.continueOperation "${REPO_RESOLVE}" '{}')"
assert_json_field "${cont_result}" '.completed' "true" "continueOperation should finish rebase"
test_pass "resolveConflict + continueOperation completes rebase"

# RESV-02/03: Resolve delete conflicts
printf ' -> RESV-02 delete-by-us resolution\n'
REPO_DELETE_US="${TEST_TMPDIR}/conflict-delete-us"
create_delete_by_us_scenario "${REPO_DELETE_US}"
(cd "${REPO_DELETE_US}" && git rebase main >/dev/null 2>&1) || true
res_keep="$(run_tool gitHex.resolveConflict "${REPO_DELETE_US}" '{"file": "file.txt", "resolution": "keep"}')"
assert_json_field "${res_keep}" '.remainingConflicts' "0" "delete conflict should be resolved with keep"
test_pass "delete-by-us resolved with keep"

printf ' -> RESV-03 delete-by-them resolution delete\n'
REPO_DELETE_THEM="${TEST_TMPDIR}/conflict-delete-them"
create_delete_by_them_scenario "${REPO_DELETE_THEM}"
(cd "${REPO_DELETE_THEM}" && git rebase main >/dev/null 2>&1) || true
res_delete="$(run_tool gitHex.resolveConflict "${REPO_DELETE_THEM}" '{"file": "file.txt", "resolution": "delete"}')"
assert_json_field "${res_delete}" '.remainingConflicts' "0" "delete conflict resolved by deleting"
test_pass "delete-by-them resolved with delete"

# CONT-02: Continue fails with unresolved conflicts
printf ' -> CONT-02 continueOperation fails when conflicts remain\n'
REPO_UNRESOLVED="${TEST_TMPDIR}/conflict-unresolved"
prepare_rebase_conflict "${REPO_UNRESOLVED}"
cont_fail="$(run_tool gitHex.continueOperation "${REPO_UNRESOLVED}" '{}')"
assert_json_field "${cont_fail}" '.completed' "false" "continueOperation should not complete with conflicts"
test_pass "continueOperation reports paused when conflicts remain"

# CONT-03: Abort rebase restores state
printf ' -> CONT-03 abortOperation restores original state\n'
REPO_ABORT="${TEST_TMPDIR}/conflict-abort"
create_conflict_scenario "${REPO_ABORT}"
head_before="$(cd "${REPO_ABORT}" && git rev-parse --short HEAD)"
(cd "${REPO_ABORT}" && git rebase main >/dev/null 2>&1) || true
abort_result="$(run_tool gitHex.abortOperation "${REPO_ABORT}" '{}')"
assert_json_field "${abort_result}" '.success' "true" "abortOperation should succeed"
head_after="$(cd "${REPO_ABORT}" && git rev-parse --short HEAD)"
assert_eq "${head_before}" "${head_after}" "HEAD should be restored after abort"
status_clean="$(cd "${REPO_ABORT}" && git status --porcelain)"
assert_eq "" "${status_clean}" "Working tree should be clean after abort"
test_pass "abortOperation restores state"

echo ""
echo "Conflict resolution tests completed"
