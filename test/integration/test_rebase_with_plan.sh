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
backup_ref="$(printf '%s' "${result}" | jq -r '.backupRef // empty')"
assert_contains "${backup_ref}" "git-hex/backup/" "backupRef should be returned"
assert_eq "3" "${after_count}" "fixup commit should be squashed (4 -> 3 commits)"
test_pass "autosquash works with empty plan"

# RBP-02: autosquash=false overrides user config
printf ' -> RBP-02 autosquash=false overrides user config\n'
REPO_NO_AUTO="${TEST_TMPDIR}/rebase-no-autosquash"
create_autosquash_config_scenario "${REPO_NO_AUTO}"
before_count_noauto="$(cd "${REPO_NO_AUTO}" && git rev-list --count HEAD)"
# User has rebase.autoSquash=true, but we pass autosquash=false
result_noauto="$(run_tool git-hex-rebaseWithPlan "${REPO_NO_AUTO}" '{"onto": "HEAD~3", "autoStash": false, "autosquash": false, "plan": []}' 60)"
after_count_noauto="$(cd "${REPO_NO_AUTO}" && git rev-list --count HEAD)"
assert_json_field "${result_noauto}" '.success' "true" "rebaseWithPlan should succeed"
# With autosquash=false, fixup commit should NOT be squashed (4 commits remain)
assert_eq "${before_count_noauto}" "${after_count_noauto}" "fixup commit should NOT be squashed when autosquash=false"
# Verify the fixup commit message is still present (wasn't squashed)
fixup_present="$(cd "${REPO_NO_AUTO}" && git log --oneline | grep -c 'fixup!' || echo "0")"
if [ "${fixup_present}" -ge 1 ]; then
	test_pass "autosquash=false prevents squashing despite user config"
else
	test_fail "fixup commit should remain when autosquash=false"
fi

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

# PLAN-06: Invalid action rejected (defense in depth; do not rely on schema validation)
printf  ' -> PLAN-06 invalid action rejected\n'
REPO_BAD_ACTION="${TEST_TMPDIR}/rebase-bad-action"
create_test_repo "${REPO_BAD_ACTION}" 3
# Use a 2-commit range so a hypothetical unvalidated `exec ...` line would still allow a successful rebase,
# ensuring this test would catch regressions (tool should fail before executing rebase).
# shellcheck disable=SC2207
bad_action_commits=($(cd "${REPO_BAD_ACTION}" && git rev-list --reverse HEAD~2..HEAD))
plan_bad_action="["
plan_bad_action="${plan_bad_action}{\"action\":\"pick\",\"commit\":\"${bad_action_commits[0]}\"},"
plan_bad_action="${plan_bad_action}{\"action\":\"exec true\",\"commit\":\"${bad_action_commits[1]}\"}"
plan_bad_action="${plan_bad_action}]"
if  run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_BAD_ACTION}" "{\"onto\": \"HEAD~2\", \"plan\": ${plan_bad_action}, \"requireComplete\": true}"; then
	test_pass "invalid action rejected"
else
	test_fail "invalid action should be rejected"
fi

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

# RBP-04: Squash with custom message preserves squash semantics and applies message
printf ' -> RBP-04 squash with custom message\n'
REPO_SQUASH_MSG="${TEST_TMPDIR}/rebase-squash-message"
create_test_repo "${REPO_SQUASH_MSG}" 3
# shellcheck disable=SC2207
squash_commits=($(cd "${REPO_SQUASH_MSG}" && git rev-list --reverse HEAD~2..HEAD))
count_before_squash="$(cd "${REPO_SQUASH_MSG}" && git rev-list --count HEAD)"
squash_message="Squashed commit message"
plan_squash="$(jq -n --arg c1 "${squash_commits[0]}" --arg c2 "${squash_commits[1]}" --arg m "${squash_message}" '[{action:"pick",commit:$c1},{action:"squash",commit:$c2,message:$m}]')"
result_squash="$(run_tool git-hex-rebaseWithPlan "${REPO_SQUASH_MSG}" "$(jq -n --argjson p "${plan_squash}" '{onto:"HEAD~2", plan:$p, requireComplete:true}')" 90)"
assert_json_field "${result_squash}" '.success' "true" "squash rebase should succeed"
count_after_squash="$(cd "${REPO_SQUASH_MSG}" && git rev-list --count HEAD)"
assert_eq "$((count_before_squash - 1))" "${count_after_squash}" "squash should reduce commit count by 1"
latest_subject="$(cd "${REPO_SQUASH_MSG}" && git log -1 --format='%s')"
assert_eq "${squash_message}" "${latest_subject}" "squash should apply custom message"
test_pass "squash with custom message works"

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
printf  ' -> PLAN-05 duplicate commit rejected\n'
REPO_DUP="${TEST_TMPDIR}/rebase-duplicate"
create_test_repo  "${REPO_DUP}" 3
dup_commit="$( cd "${REPO_DUP}" && git rev-list --reverse HEAD~2..HEAD | head -n1)"
plan_dup="[ {\"action\":\"pick\",\"commit\":\"${dup_commit}\"}, {\"action\":\"pick\",\"commit\":\"${dup_commit}\"} ]"
if  run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_DUP}" "{\"onto\": \"HEAD~2\", \"plan\": ${plan_dup}, \"requireComplete\": true}"; then
	test_pass "duplicate commit rejected"
else
	test_fail "duplicate commit should fail validation"
fi

# ONTO-01: onto must resolve to a commit (not a file path)
printf  ' -> ONTO-01 onto validation rejects filesystem paths\n'
REPO_ONTO_PATH="${TEST_TMPDIR}/rebase-onto-path"
create_test_repo  "${REPO_ONTO_PATH}" 2
(
	cd "${REPO_ONTO_PATH}"
	echo "not a ref" >onto-path.txt
	git add onto-path.txt
	git commit -m "Add onto-path file" >/dev/null 2>&1
)
if  run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_ONTO_PATH}" '{"onto": "onto-path.txt", "plan": []}'; then
	test_pass "onto path rejected"
else
	test_fail "onto should be rejected when it is a path"
fi

# RBC-02: abortOnConflict=false pauses rebase
printf  ' -> RBC-02 abortOnConflict=false pauses on conflict\n'
REPO_CONFLICT="${TEST_TMPDIR}/rebase-conflict-pause"
create_conflict_scenario  "${REPO_CONFLICT}"
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

pause_backup_ref="$(printf '%s' "${pause_result}" | jq -r '.backupRef // empty')"
if [ -n "${pause_backup_ref}" ]; then
	assert_contains "${pause_backup_ref}" "git-hex/backup/" "paused response should include backupRef"
	test_pass "paused response includes backupRef"
else
	test_fail "paused response should include backupRef"
fi

# RBC-02b: continueOperation records last-head for paused git-hex rebase
printf  ' -> RBC-02b continueOperation records last-head after completion\n'
backup_suffix_path="$(cd "${REPO_CONFLICT}" && git rev-parse --git-path git-hex-last-backup)"
backup_suffix="$(cd "${REPO_CONFLICT}" && head -1 "${backup_suffix_path}" 2>/dev/null || true)"
backup_suffix="$(printf '%s' "${backup_suffix}" | tr -d '\r\n')"
if [ -z "${backup_suffix}" ]; then
	test_fail "git-hex-last-backup suffix missing for paused rebase"
fi

echo "resolved content" >"${REPO_CONFLICT}/conflict.txt"
res_result="$(run_tool git-hex-resolveConflict "${REPO_CONFLICT}" '{"file":"conflict.txt"}')"
assert_json_field "${res_result}" '.remainingConflicts' "0" "all conflicts should be resolved"

cont_result="$(run_tool git-hex-continueOperation "${REPO_CONFLICT}" '{}')"
assert_json_field "${cont_result}" '.completed' "true" "continueOperation should finish paused rebase"

head_after_continue="$(cd "${REPO_CONFLICT}" && git rev-parse HEAD)"
recorded_head="$(cd "${REPO_CONFLICT}" && git rev-parse --verify "refs/git-hex/last-head/${backup_suffix}^{commit}" 2>/dev/null || echo "")"
if [ -z "${recorded_head}" ]; then
	test_fail "refs/git-hex/last-head/${backup_suffix} not recorded after continueOperation"
fi
assert_eq "${head_after_continue}" "${recorded_head}" "last-head should match HEAD after continueOperation"
test_pass "continueOperation recorded last-head for paused rebase"

# RBC-03: autoStash works with abortOnConflict=false (native)
printf  ' -> RBC-03 autoStash works with abortOnConflict=false\n'
REPO_AUTOSTASH="${TEST_TMPDIR}/rebase-autostash-native"
create_dirty_repo  "${REPO_AUTOSTASH}"
result_autostash="$( run_tool git-hex-rebaseWithPlan "${REPO_AUTOSTASH}" '{"onto": "main", "abortOnConflict": false, "autoStash": true}')"
assert_json_field  "${result_autostash}" '.paused' "false" "rebase should complete without pause in clean scenario"
if  ! (cd "${REPO_AUTOSTASH}" && git diff --quiet); then
	test_pass "native autoStash restored working tree"
else
	test_fail "dirty changes should be restored after rebase"
fi

# RBC-04: Output containing the word "conflict" does not imply a conflict pause (e.g., hooks)
printf  ' -> RBC-04 output containing \"conflict\" is not misclassified as a conflict pause\n'
REPO_FALSE_CONFLICT="${TEST_TMPDIR}/rebase-false-conflict-word"
mkdir  -p "${REPO_FALSE_CONFLICT}"
(
	cd "${REPO_FALSE_CONFLICT}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test User"
	git config commit.gpgsign false

	echo "base a" >a.txt
	echo "base b" >b.txt
	git add a.txt b.txt
	git commit -m "Base" >/dev/null

	git checkout -b feature >/dev/null 2>&1
	echo "feature change" >a.txt
	git add a.txt
	git commit -m "feat: word conflict in subject" >/dev/null

	git checkout main >/dev/null 2>&1
	echo "main change" >b.txt
	git add b.txt
	git commit -m "Main change" >/dev/null

	git checkout feature >/dev/null 2>&1

	mkdir -p .githooks
	cat >.githooks/pre-rebase <<'EOF'
#!/usr/bin/env bash
echo "conflict: deny rebase (hook)" >&2
exit 1
EOF
	chmod +x .githooks/pre-rebase
	git config core.hooksPath .githooks
)
head_before_false_conflict="$( cd "${REPO_FALSE_CONFLICT}" && git rev-parse HEAD)"
if  run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_FALSE_CONFLICT}" '{"onto":"main","abortOnConflict":false,"plan":[]}'; then
	test_pass "non-conflict failure is not treated as conflict pause"
else
	test_fail "rebaseWithPlan should fail (not pause) even if output contains 'conflict'"
fi
if  [ -d "${REPO_FALSE_CONFLICT}/.git/rebase-merge" ] || [ -d "${REPO_FALSE_CONFLICT}/.git/rebase-apply" ]; then
	test_fail "rebaseWithPlan should abort and not leave a paused rebase state on non-conflict failures"
else
	test_pass "non-conflict failure aborted cleanly"
fi
head_after_false_conflict="$( cd "${REPO_FALSE_CONFLICT}" && git rev-parse HEAD)"
assert_eq  "${head_before_false_conflict}" "${head_after_false_conflict}" "HEAD should be restored after non-conflict rebase failure"

echo  ""
echo  "rebaseWithPlan tests completed"
