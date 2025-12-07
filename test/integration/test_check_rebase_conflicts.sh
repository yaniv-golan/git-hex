#!/usr/bin/env bash
# Integration tests for gitHex.checkRebaseConflicts
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

echo "=== checkRebaseConflicts Tests ==="

# CHK-01: Clean rebase predicted
printf ' -> CHK-01 predicts clean rebase\n'
REPO_CLEAN="${TEST_TMPDIR}/check-clean"
create_branch_scenario "${REPO_CLEAN}"
result_clean="$(run_tool gitHex.checkRebaseConflicts "${REPO_CLEAN}" '{"onto": "main"}')"
assert_json_field "${result_clean}" '.wouldConflict' "false" "should predict clean rebase"
assert_json_field "${result_clean}" '.limitExceeded' "false" "limitExceeded should be false"
test_pass "clean rebase predicted"

# CHK-02: Conflict predicted
printf ' -> CHK-02 predicts conflict\n'
REPO_CONFLICT="${TEST_TMPDIR}/check-conflict"
create_conflict_scenario "${REPO_CONFLICT}"
result_conflict="$(run_tool gitHex.checkRebaseConflicts "${REPO_CONFLICT}" '{"onto": "main"}')"
assert_json_field "${result_conflict}" '.wouldConflict' "true" "should predict conflict"
test_pass "conflict predicted"

# CHK-03/04: First conflict identified, subsequent unknown
printf ' -> CHK-03 first conflict identified, later unknown\n'
REPO_MULTI="${TEST_TMPDIR}/check-multi"
mkdir -p "${REPO_MULTI}"
(
	cd "${REPO_MULTI}"
	git init --initial-branch=main
	_configure_test_repo
	echo "base" >base.txt
	git add base.txt && git commit -m "Base"
	git checkout -b feature
	echo "clean change" >clean.txt
	git add clean.txt && git commit -m "Clean change"
	echo "conflict" >conflict.txt
	git add conflict.txt && git commit -m "Conflicting change"
	echo "post conflict" >later.txt
	git add later.txt && git commit -m "Later change"
	git checkout main
	echo "main change" >conflict.txt
	git add conflict.txt && git commit -m "Main conflict"
	git checkout feature
)
result_multi="$(run_tool gitHex.checkRebaseConflicts "${REPO_MULTI}" '{"onto": "main"}')"
first_prediction="$(printf '%s' "${result_multi}" | jq -r '.commits[1].prediction')"
third_prediction="$(printf '%s' "${result_multi}" | jq -r '.commits[2].prediction')"
assert_eq "conflict" "${first_prediction}" "second commit should be predicted conflict"
assert_eq "unknown" "${third_prediction}" "commits after conflict marked unknown"
test_pass "predictions stop after first conflict"

# CHK-14/15/16: maxCommits limits simulation
# Using 20 commits with maxCommits=15 to trigger limitExceeded while keeping test fast
printf ' -> CHK-14/15 limitExceeded when exceeding maxCommits\n'
REPO_LARGE="${TEST_TMPDIR}/check-large"
create_large_history_scenario "${REPO_LARGE}" 20
result_limit="$(run_tool gitHex.checkRebaseConflicts "${REPO_LARGE}" '{"onto": "main", "maxCommits": 15}' 90)"
assert_json_field "${result_limit}" '.limitExceeded' "true" "limit should be exceeded for large history"
checked="$(printf '%s' "${result_limit}" | jq -r '.checkedCommits')"
total="$(printf '%s' "${result_limit}" | jq -r '.totalCommits')"
assert_eq "15" "${checked}" "checkedCommits should respect maxCommits"
expected_total="$(cd "${REPO_LARGE}" && git rev-list --count main..HEAD)"
assert_eq "${expected_total}" "${total}" "totalCommits should include commits in range"
test_pass "maxCommits respected with limitExceeded"

echo ""
echo "checkRebaseConflicts tests completed"
