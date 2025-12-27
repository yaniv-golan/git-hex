#!/usr/bin/env bash
# Cross-cutting edge case tests
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

echo "=== Edge Case Tests ==="

# EDGE-30: stashNotRestored is boolean
printf ' -> EDGE-30 stashNotRestored type is boolean\n'
REPO_STASH_TYPE="${TEST_TMPDIR}/edge-stash-type"
create_staged_dirty_repo "${REPO_STASH_TYPE}"
echo "conflict change" >>"${REPO_STASH_TYPE}/file.txt"
result_stash="$(run_tool git-hex-amendLastCommit "${REPO_STASH_TYPE}" '{"autoStash": true, "message": "type check"}')"
type_field="$(printf '%s' "${result_stash}" | jq -r '(.stashNotRestored|type)')" || type_field="missing"
assert_eq "boolean" "${type_field}" "stashNotRestored should be boolean"
test_pass "stashNotRestored type correct"

# EDGE-31: limitExceeded is boolean
# Using 15 commits with maxCommits=10 to trigger limitExceeded while keeping test fast
printf ' -> EDGE-31 limitExceeded type is boolean\n'
REPO_LIMIT_TYPE="${TEST_TMPDIR}/edge-limit-type"
create_large_history_scenario "${REPO_LIMIT_TYPE}" 15
result_limit="$(run_tool git-hex-checkRebaseConflicts "${REPO_LIMIT_TYPE}" '{"onto": "main", "maxCommits": 10}' 90)"
limit_type="$(printf '%s' "${result_limit}" | jq -r '(.limitExceeded|type)')" || limit_type="missing"
assert_eq "boolean" "${limit_type}" "limitExceeded should be boolean"
test_pass "limitExceeded type correct"

# EDGE-32: rebasePaused is boolean
printf ' -> EDGE-32 rebasePaused type is boolean\n'
REPO_REBASE_PAUSED="${TEST_TMPDIR}/edge-rebase-paused"
create_split_subsequent_conflict_scenario "${REPO_REBASE_PAUSED}"
target_commit="$(cd "${REPO_REBASE_PAUSED}" && git rev-list --reverse HEAD | sed -n '2p')"
args_paused="$(
	cat <<JSON
{
  "commit": "${target_commit}",
  "splits": [
    { "files": ["conflict.txt"], "message": "One" },
    { "files": ["other.txt"], "message": "Two" }
  ]
}
JSON
)"
result_paused="$(run_tool git-hex-splitCommit "${REPO_REBASE_PAUSED}" "${args_paused}" 120)"
paused_type="$(printf '%s' "${result_paused}" | jq -r '(.rebasePaused|type)')" || paused_type="missing"
assert_eq "boolean" "${paused_type}" "rebasePaused should be boolean"
test_pass "rebasePaused type correct"

# EDGE-33: Leading-dash filenames are handled safely in conflict workflows
printf ' -> EDGE-33 leading-dash filenames work in conflict workflows\n'
REPO_DASH="${TEST_TMPDIR}/edge-dash-filename"
mkdir -p "${REPO_DASH}"
(
	cd "${REPO_DASH}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test User"
	git config commit.gpgsign false

	echo "original" >-dash.txt
	git add -- -dash.txt
	git commit -m "Base" >/dev/null

	git checkout -b feature >/dev/null 2>&1
	git rm -f -- -dash.txt >/dev/null 2>&1
	git commit -m "Delete" >/dev/null

	git checkout main >/dev/null 2>&1
	echo "main modified" >-dash.txt
	git add -- -dash.txt
	git commit -m "Modify" >/dev/null

	git checkout feature >/dev/null 2>&1
	git merge main >/dev/null 2>&1 || true
	if [ ! -f ".git/MERGE_HEAD" ]; then
		echo "WARNING: expected MERGE_HEAD not found; merge did not enter conflict state" >&2
		exit 1
	fi
)
dash_status="$(run_tool git-hex-getConflictStatus "${REPO_DASH}" '{"includeContent": false}')"
assert_json_field "${dash_status}" '.inConflict' "true" "repo should be in conflict"
dash_file_type="$(printf '%s' "${dash_status}" | jq -r '.conflictingFiles[] | select(.path=="-dash.txt") | .conflictType')"
assert_eq "deleted_by_us" "${dash_file_type}" "should detect delete/modify conflict on -dash.txt"
resolve_dash="$(run_tool git-hex-resolveConflict "${REPO_DASH}" '{"file":"-dash.txt","resolution":"keep"}')"
assert_json_field "${resolve_dash}" '.success' "true" "resolveConflict should succeed for -dash.txt"
remaining_dash="$(printf '%s' "${resolve_dash}" | jq -r '.remainingConflicts')"
assert_eq "0" "${remaining_dash}" "should have no remaining conflicts after resolving -dash.txt"
test_pass "leading-dash filename handled"
(cd "${REPO_DASH}" && git merge --abort >/dev/null 2>&1) || true

echo ""
echo "Edge case tests completed"
