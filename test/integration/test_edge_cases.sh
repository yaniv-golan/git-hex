#!/usr/bin/env bash
# Cross-cutting edge case tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../common/env.sh"
. "${SCRIPT_DIR}/../common/assert.sh"
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_verify_framework
test_create_tmpdir

echo "=== Edge Case Tests ==="

# EDGE-30: stashNotRestored is boolean
printf ' -> EDGE-30 stashNotRestored type is boolean\n'
REPO_STASH_TYPE="${TEST_TMPDIR}/edge-stash-type"
create_staged_dirty_repo "${REPO_STASH_TYPE}"
echo "conflict change" >>"${REPO_STASH_TYPE}/file.txt"
result_stash="$(run_tool gitHex.amendLastCommit "${REPO_STASH_TYPE}" '{"autoStash": true, "message": "type check"}')"
type_field="$(printf '%s' "${result_stash}" | jq -r '(.stashNotRestored|type)')" || type_field="missing"
assert_eq "boolean" "${type_field}" "stashNotRestored should be boolean"
test_pass "stashNotRestored type correct"

# EDGE-31: limitExceeded is boolean
printf ' -> EDGE-31 limitExceeded type is boolean\n'
REPO_LIMIT_TYPE="${TEST_TMPDIR}/edge-limit-type"
create_large_history_scenario "${REPO_LIMIT_TYPE}" 120
result_limit="$(run_tool gitHex.checkRebaseConflicts "${REPO_LIMIT_TYPE}" '{"onto": "main", "maxCommits": 10}')"
limit_type="$(printf '%s' "${result_limit}" | jq -r '(.limitExceeded|type)')" || limit_type="missing"
assert_eq "boolean" "${limit_type}" "limitExceeded should be boolean"
test_pass "limitExceeded type correct"

# EDGE-32: rebasePaused is boolean
printf ' -> EDGE-32 rebasePaused type is boolean\n'
REPO_REBASE_PAUSED="${TEST_TMPDIR}/edge-rebase-paused"
create_split_subsequent_conflict_scenario "${REPO_REBASE_PAUSED}"
target_commit="$(cd "${REPO_REBASE_PAUSED}" && git rev-list --reverse HEAD | sed -n '2p')"
args_paused="$(
	cat             <<JSON
{
  "commit": "${target_commit}",
  "splits": [
    { "files": ["conflict.txt"], "message": "One" },
    { "files": ["other.txt"], "message": "Two" }
  ]
}
JSON
)"
result_paused="$(run_tool gitHex.splitCommit "${REPO_REBASE_PAUSED}" "${args_paused}" 120)"
paused_type="$(printf '%s' "${result_paused}" | jq -r '(.rebasePaused|type)')" || paused_type="missing"
assert_eq "boolean" "${paused_type}" "rebasePaused should be boolean"
test_pass "rebasePaused type correct"

echo ""
echo "Edge case tests completed"
