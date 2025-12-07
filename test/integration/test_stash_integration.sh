#!/usr/bin/env bash
# Integration tests for stash integration across tools
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

echo "=== Stash Integration Tests ==="

# Helper: count stashes in repo
stash_count() {
	local repo="$1"
	(cd "${repo}" && git stash list 2>/dev/null | wc -l | tr -d ' ')
}

stash_top_hash() {
	local repo="$1"
	(cd "${repo}" && git stash list --pretty='%H' -n 1 2>/dev/null || echo "")
}

# STASH-01: autoStash creates stash when dirty
printf ' -> STASH-01 autoStash creates stash when dirty\n'
REPO="${TEST_TMPDIR}/stash-dirty-rebase"
create_branch_scenario "${REPO}"
echo "dirty change" >>"${REPO}/feature1.txt"
before_stash="$(stash_count "${REPO}")"
result="$(run_tool gitHex.rebaseWithPlan "${REPO}" '{"onto": "main", "autoStash": true}' 60)"
after_stash="$(stash_count "${REPO}")"
assert_json_field "${result}" '.success' "true" "rebaseWithPlan should succeed with autoStash"
assert_eq "${before_stash}" "${after_stash}" "autoStash should pop stash after rebase"
if ! (cd "${REPO}" && git diff --quiet); then
	test_pass "autoStash restored working tree state"
else
	test_fail "dirty change should be restored after rebase"
fi

# STASH-02: autoStash skipped when clean
printf ' -> STASH-02 autoStash skipped when clean\n'
REPO2="${TEST_TMPDIR}/stash-clean-rebase"
create_branch_scenario "${REPO2}"
clean_before="$(stash_count "${REPO2}")"
result="$(run_tool gitHex.rebaseWithPlan "${REPO2}" '{"onto": "main", "autoStash": true}' 60)"
clean_after="$(stash_count "${REPO2}")"
assert_json_field "${result}" '.success' "true" "rebaseWithPlan should succeed on clean repo"
assert_eq "${clean_before}" "${clean_after}" "no stash should be created for clean repo"
test_pass "autoStash skipped when clean"

# STASH-03: autoStash=false fails on dirty
printf ' -> STASH-03 autoStash=false fails on dirty\n'
REPO3="${TEST_TMPDIR}/stash-dirty-no-autostash"
create_branch_scenario "${REPO3}"
echo "dirty change" >>"${REPO3}/feature1.txt"
if run_tool_expect_fail gitHex.rebaseWithPlan "${REPO3}" '{"onto": "main", "autoStash": false}' 60; then
	test_pass "rebaseWithPlan rejects dirty repo without autoStash"
else
	test_fail "rebaseWithPlan should fail when dirty and autoStash=false"
fi

# STASH-04: autoStash default is false
printf ' -> STASH-04 autoStash default is false\n'
REPO4="${TEST_TMPDIR}/stash-dirty-default"
create_branch_scenario "${REPO4}"
echo "dirty change" >>"${REPO4}/feature2.txt"
if run_tool_expect_fail gitHex.rebaseWithPlan "${REPO4}" '{"onto": "main"}' 60; then
	test_pass "rebaseWithPlan defaults to failing on dirty repo"
else
	test_fail "rebaseWithPlan should fail without autoStash on dirty repo"
fi

# STASH-10: cherryPickSingle autoStash works
printf ' -> STASH-10 cherryPickSingle autoStash works\n'
REPO5="${TEST_TMPDIR}/stash-cherry-pick"
create_branch_scenario "${REPO5}"
source_commit="$(cd "${REPO5}" && git rev-parse main)"
echo "dirty change" >>"${REPO5}/feature1.txt"
before="$(stash_count "${REPO5}")"
result="$(run_tool gitHex.cherryPickSingle "${REPO5}" "{\"commit\": \"${source_commit}\", \"autoStash\": true}")"
after="$(stash_count "${REPO5}")"
assert_json_field "${result}" '.success' "true" "cherryPickSingle should succeed with autoStash"
assert_eq "${before}" "${after}" "stash should be restored after cherry-pick"
test_pass "cherryPickSingle autoStash creates and restores stash"

# STASH-11: cherryPickSingle autoStash blocked with abortOnConflict=false
printf ' -> STASH-11 autoStash rejected when abortOnConflict=false\n'
REPO6="${TEST_TMPDIR}/stash-cherry-pick-block"
create_branch_scenario "${REPO6}"
echo "dirty change" >>"${REPO6}/feature1.txt"
if run_tool_expect_fail gitHex.cherryPickSingle "${REPO6}" "{\"commit\": \"main\", \"autoStash\": true, \"abortOnConflict\": false}"; then
	test_pass "autoStash rejected when abortOnConflict=false"
else
	test_fail "autoStash should be rejected with abortOnConflict=false"
fi

# STASH-12: amendLastCommit autoStash works
printf ' -> STASH-12 amendLastCommit autoStash works\n'
REPO7="${TEST_TMPDIR}/stash-amend"
create_staged_dirty_repo "${REPO7}"
echo "unstaged change" >>"${REPO7}/file.txt"
before_amend="$(stash_count "${REPO7}")"
result="$(run_tool gitHex.amendLastCommit "${REPO7}" '{"autoStash": true, "message": "Amended message"}')"
after_amend="$(stash_count "${REPO7}")"
assert_json_field "${result}" '.success' "true" "amendLastCommit should succeed with autoStash"
assert_eq "${before_amend}" "${after_amend}" "stash should be restored after amend"
test_pass "amendLastCommit autoStash preserves unstaged changes"

# STASH-13: amendLastCommit restores stash on failure
printf ' -> STASH-13 amendLastCommit restores stash on failure\n'
REPO8="${TEST_TMPDIR}/stash-amend-failure"
create_staged_dirty_repo "${REPO8}"
echo "unstaged fail change" >>"${REPO8}/file.txt"
# Commit-msg hook to force failure
mkdir -p "${REPO8}/.git/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' >"${REPO8}/.git/hooks/commit-msg"
chmod +x "${REPO8}/.git/hooks/commit-msg"
before_hook="$(stash_count "${REPO8}")"
if run_tool_expect_fail gitHex.amendLastCommit "${REPO8}" '{"autoStash": true, "message": "Should fail"}'; then
	after_hook="$(stash_count "${REPO8}")"
	assert_eq "${before_hook}" "${after_hook}" "stash should be restored when amend fails"
	test_pass "amendLastCommit restores stash on failure"
else
	test_fail "amendLastCommit should fail due to hook"
fi

# STASH-14: stashNotRestored flag on pop conflict
printf ' -> STASH-14 stashNotRestored reported on pop conflict\n'
REPO9="${TEST_TMPDIR}/stash-pop-conflict"
create_staged_dirty_repo "${REPO9}"
# Stage an additional change, then introduce an unstaged change that will be stashed
echo "staged change" >>"${REPO9}/file.txt"
(cd "${REPO9}" && git add file.txt)
echo "unstaged original" >>"${REPO9}/file.txt"
# Post-commit hook mutates the file so stash apply fails
mkdir -p "${REPO9}/.git/hooks"
cat >"${REPO9}/.git/hooks/post-commit"  <<'EOF'
#!/usr/bin/env bash
echo "post-commit change" > file.txt
EOF
chmod +x "${REPO9}/.git/hooks/post-commit"

result="$(run_tool gitHex.amendLastCommit "${REPO9}" '{"autoStash": true, "message": "Trigger stash pop conflict"}')"
stash_list_after="$(stash_count "${REPO9}")"
if [ "${stash_list_after}" -gt 0 ]; then
	assert_json_field "${result}" '.stashNotRestored' "true" "stashNotRestored should be true when pop fails"
	test_pass "stashNotRestored reported when stash pop conflicts"
else
	test_fail "stash should remain when pop fails"
fi

# STASH-15: staged-only changes with existing stash remain untouched
printf ' -> STASH-15 existing stash untouched with staged-only autoStash\n'
REPO_EXISTING="${TEST_TMPDIR}/stash-existing"
create_staged_dirty_repo "${REPO_EXISTING}"
# Create a user stash before running the tool
echo "user dirty" >>"${REPO_EXISTING}/file.txt"
(cd "${REPO_EXISTING}" && git stash push -m "user-stash" >/dev/null 2>&1)
user_stash_top="$(stash_top_hash "${REPO_EXISTING}")"
# Leave only staged changes (no unstaged)
(cd "${REPO_EXISTING}" && git add file.txt)
result_existing="$(run_tool gitHex.amendLastCommit "${REPO_EXISTING}" '{"autoStash": true, "message": "Amend with staged only"}')"
assert_json_field "${result_existing}" '.success' "true" "amendLastCommit should succeed with staged-only changes"
after_count_existing="$(stash_count "${REPO_EXISTING}")"
after_top_existing="$(stash_top_hash "${REPO_EXISTING}")"
assert_eq "${after_count_existing}" "1" "existing stash count should remain unchanged"
if [ "${user_stash_top}" = "${after_top_existing}" ]; then
	test_pass "existing user stash left untouched when no new stash created"
else
	test_fail "existing stash should not be popped or replaced"
fi

# STASH-20: Untracked files NOT stashed
printf ' -> STASH-20 untracked files not stashed\n'
REPO10="${TEST_TMPDIR}/stash-untracked"
create_untracked_files_scenario "${REPO10}"
result="$(run_tool gitHex.rebaseWithPlan "${REPO10}" '{"onto": "main", "autoStash": true}' 60)"
assert_json_field "${result}" '.success' "true" "rebaseWithPlan should ignore untracked files"
if [ -f "${REPO10}/untracked.txt" ] && [ -f "${REPO10}/untracked_dir/file.txt" ]; then
	test_pass "untracked files remain after autoStash"
else
	test_fail "untracked files should not be stashed"
fi

# STASH-21: Untracked files don't block rebase
printf ' -> STASH-21 untracked files do not block rebase\n'
REPO11="${TEST_TMPDIR}/stash-untracked-clean"
create_untracked_files_scenario "${REPO11}"
result="$(run_tool gitHex.rebaseWithPlan "${REPO11}" '{"onto": "main"}' 60)"
assert_json_field "${result}" '.success' "true" "rebaseWithPlan should succeed when only untracked files exist"
test_pass "untracked files do not block rebase"

echo ""
echo "Stash integration tests completed"
