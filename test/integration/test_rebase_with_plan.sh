#!/usr/bin/env bash
# Integration tests for git-hex-rebaseWithPlan
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

echo "=== rebaseWithPlan Tests ==="

# Helper to list commits in range (oldest first)
range_commits() {
	local repo="$1"
	local onto="$2"
	(cd "${repo}" && git rev-list --reverse "${onto}..HEAD")
}

# RBP-01: Empty plan with autosquash squashes fixups
printf ' -> RBP-01 autosquash squashes fixup commits\n'
REPO_AUTO="${TEST_TMPDIR}/rebase-autosquash"
create_fixup_scenario "${REPO_AUTO}"
# shellcheck disable=SC2034
before_count="$(cd "${REPO_AUTO}" && git rev-list --count HEAD)"
result="$(run_tool git-hex-rebaseWithPlan "${REPO_AUTO}" '{"onto": "HEAD~3", "autoStash": false, "autosquash": true, "plan": []}' 60)"
after_count="$(cd "${REPO_AUTO}" && git rev-list --count HEAD)"
assert_json_field "${result}" '.success' "true" "rebaseWithPlan should succeed"
assert_eq "3" "${after_count}" "fixup commit should be squashed (4 -> 3 commits)"
test_pass "autosquash works with empty plan"

# RBP-03: Drop a commit using complete plan
printf ' -> RBP-03 drop commit using plan\n'
REPO_DROP="${TEST_TMPDIR}/rebase-drop"
create_branch_scenario "${REPO_DROP}"
# shellcheck disable=SC2207
commits=($(range_commits "${REPO_DROP}" "main"))
plan="["
plan="${plan}{\"action\":\"pick\",\"commit\":\"${commits[0]}\"},"
plan="${plan}{\"action\":\"drop\",\"commit\":\"${commits[1]}\"}"
plan="${plan}]"
result="$(run_tool git-hex-rebaseWithPlan "${REPO_DROP}" "{\"onto\": \"main\", \"plan\": ${plan}, \"requireComplete\": true}")"
assert_json_field "${result}" '.success' "true" "rebaseWithPlan should succeed dropping commit"
new_count="$(cd "${REPO_DROP}" && git rev-list --count HEAD)"
assert_eq "3" "${new_count}" "history should have one fewer commit after drop"
test_pass "drop action works"

# MSG-01..06/11: Messages with special characters preserved
printf ' -> MSG-* reword preserves special characters\n'
REPO_MSG="${TEST_TMPDIR}/rebase-messages"
create_test_repo "${REPO_MSG}" 2
# shellcheck disable=SC2016
messages=('Say "hello"' "It's working" 'Fix $PATH issue' 'Use $(whoami)' 'Run `ls`' 'Path: C:\\Users' '修复 🐛 bug')
for msg in "${messages[@]}"; do
	target="$(cd "${REPO_MSG}" && git rev-list --reverse HEAD~1..HEAD | tail -n 1)"
	plan_json="$(jq -n --arg commit "${target}" --arg message "${msg}" '{onto: "HEAD~1", plan: [{action: "reword", commit: $commit, message: $message}], requireComplete: true}')"
	result="$(run_tool git-hex-rebaseWithPlan "${REPO_MSG}" "${plan_json}")"
	assert_json_field "${result}" '.success' "true" "reword should succeed"
	latest_msg="$(cd "${REPO_MSG}" && git log -1 --format='%s')"
	assert_eq "${msg}" "${latest_msg}" "commit message should match input"
done
test_pass "reword handles special characters safely"

# MSG-08/09: Message with newline or TAB rejected
printf ' -> MSG-08/09 message validation rejects newline/TAB\n'
REPO_BAD_MSG="${TEST_TMPDIR}/rebase-bad-message"
create_test_repo "${REPO_BAD_MSG}" 2
target_bad="$(cd "${REPO_BAD_MSG}" && git rev-list --reverse HEAD~1..HEAD | tail -n 1)"
if run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_BAD_MSG}" "{\"onto\": \"HEAD~1\", \"plan\": [{\"action\": \"reword\", \"commit\": \"${target_bad}\", \"message\": \"Line1\nLine2\"}], \"requireComplete\": true}"; then
	test_pass "newline in message rejected"
else
	test_fail "message with newline should be rejected"
fi
if run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_BAD_MSG}" "{\"onto\": \"HEAD~1\", \"plan\": [{\"action\": \"reword\", \"commit\": \"${target_bad}\", \"message\": \"Col1\tCol2\"}], \"requireComplete\": true}"; then
	test_pass "TAB in message rejected"
else
	test_fail "message with TAB should be rejected"
fi

# PLAN-04: requireComplete=true missing commit fails
printf ' -> PLAN-04 missing commit when requireComplete=true\n'
REPO_REQ="${TEST_TMPDIR}/rebase-require-complete"
create_test_repo "${REPO_REQ}" 3
# shellcheck disable=SC2207
commits_req=($(cd "${REPO_REQ}" && git rev-list --reverse HEAD~2..HEAD))
if run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_REQ}" "{\"onto\": \"HEAD~2\", \"plan\": [{\"action\": \"pick\", \"commit\": \"${commits_req[0]}\"}], \"requireComplete\": true}"; then
	test_pass "requireComplete enforces full list"
else
	test_fail "missing commits should fail when requireComplete=true"
fi

# PLAN-05: Duplicate commit rejected
printf ' -> PLAN-05 duplicate commit rejected\n'
REPO_DUP="${TEST_TMPDIR}/rebase-duplicate"
create_test_repo "${REPO_DUP}" 3
dup_commit="$(cd "${REPO_DUP}" && git rev-list --reverse HEAD~2..HEAD | head -n1)"
plan_dup="[ {\"action\":\"pick\",\"commit\":\"${dup_commit}\"}, {\"action\":\"pick\",\"commit\":\"${dup_commit}\"} ]"
if run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_DUP}" "{\"onto\": \"HEAD~2\", \"plan\": ${plan_dup}, \"requireComplete\": true}"; then
	test_pass "duplicate commit rejected"
else
	test_fail "duplicate commit should fail validation"
fi

# RBC-02: abortOnConflict=false pauses rebase
printf ' -> RBC-02 abortOnConflict=false pauses on conflict\n'
REPO_CONFLICT="${TEST_TMPDIR}/rebase-conflict-pause"
create_conflict_scenario "${REPO_CONFLICT}"
head_before_conflict="$(cd "${REPO_CONFLICT}" && git rev-parse HEAD)"
pause_result="$(run_tool git-hex-rebaseWithPlan "${REPO_CONFLICT}" '{"onto": "main", "abortOnConflict": false}')"
assert_json_field "${pause_result}" '.paused' "true" "rebase should pause on conflict"
if [ -d "${REPO_CONFLICT}/.git/rebase-merge" ] || [ -d "${REPO_CONFLICT}/.git/rebase-apply" ]; then
	test_pass "rebase left in paused state for inspection"
else
	test_fail "rebase should remain paused"
fi
pause_head_after="$(printf '%s' "${pause_result}" | jq -r '.headAfter // empty')"
pause_head_before_field="$(printf '%s' "${pause_result}" | jq -r '.headBefore // empty')"
if [ -n "${pause_head_after}" ] && [ -n "${pause_head_before_field}" ]; then
	assert_eq "${head_before_conflict}" "${pause_head_before_field}" "headBefore should match starting HEAD"
	test_pass "paused response includes headBefore/headAfter"
else
	test_fail "paused response should include headBefore/headAfter"
fi

# RBC-03: autoStash works with abortOnConflict=false (native)
printf ' -> RBC-03 autoStash works with abortOnConflict=false\n'
REPO_AUTOSTASH="${TEST_TMPDIR}/rebase-autostash-native"
create_dirty_repo "${REPO_AUTOSTASH}"
result_autostash="$(run_tool git-hex-rebaseWithPlan "${REPO_AUTOSTASH}" '{"onto": "main", "abortOnConflict": false, "autoStash": true}')"
assert_json_field "${result_autostash}" '.paused' "false" "rebase should complete without pause in clean scenario"
if ! (cd "${REPO_AUTOSTASH}" && git diff --quiet); then
	test_pass "native autoStash restored working tree"
else
	test_fail "dirty changes should be restored after rebase"
fi

echo ""
echo "rebaseWithPlan tests completed"
