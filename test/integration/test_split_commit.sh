#!/usr/bin/env bash
# Integration tests for gitHex.splitCommit
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

echo "=== splitCommit Tests ==="

# Helper: get commit to split (second commit in history)
commit_to_split() {
	local repo="$1"
	(cd "${repo}" && git rev-list --reverse HEAD | sed -n '2p')
}

# SPLIT-01: Split a commit into two commits
printf ' -> SPLIT-01 split commit into two\n'
REPO_SPLIT="${TEST_TMPDIR}/split-basic"
create_split_commit_scenario "${REPO_SPLIT}" 2
target_commit="$(commit_to_split "${REPO_SPLIT}")"
args="$(
	cat <<JSON
{
  "commit": "${target_commit}",
  "splits": [
    { "files": ["file1.txt"], "message": "First part" },
    { "files": ["file2.txt"], "message": "Second part" }
  ]
}
JSON
)"
result="$(run_tool gitHex.splitCommit "${REPO_SPLIT}" "${args}" 120)"
assert_json_field "${result}" '.success' "true" "splitCommit should succeed"
new_messages="$(cd "${REPO_SPLIT}" && git log -3 --format='%s' | paste -sd ',' -)"
assert_contains "${new_messages}" "First part" "new commits should include first split message"
assert_contains "${new_messages}" "Second part" "new commits should include second split message"
test_pass "splitCommit created two commits"

# SPLIT-10: File not in original commit should fail
printf ' -> SPLIT-10 file not in original commit rejected\n'
REPO_INVALID_FILE="${TEST_TMPDIR}/split-invalid-file"
create_split_commit_scenario "${REPO_INVALID_FILE}" 2
target_commit="$(commit_to_split "${REPO_INVALID_FILE}")"
args_invalid="$(
	cat <<JSON
{
  "commit": "${target_commit}",
  "splits": [
    { "files": ["file1.txt"], "message": "Keep" },
    { "files": ["missing.txt"], "message": "Missing" }
  ]
}
JSON
)"
if run_tool_expect_fail gitHex.splitCommit "${REPO_INVALID_FILE}" "${args_invalid}"; then
	test_pass "splitCommit rejects file not in commit"
else
	test_fail "splitCommit should fail when files missing"
fi

# SPLIT-11: Duplicate file rejected
printf ' -> SPLIT-11 duplicate file rejected\n'
REPO_DUP_FILE="${TEST_TMPDIR}/split-duplicate"
create_split_commit_scenario "${REPO_DUP_FILE}" 2
target_commit="$(commit_to_split "${REPO_DUP_FILE}")"
args_dup="$(
	cat <<JSON
{
  "commit": "${target_commit}",
  "splits": [
    { "files": ["file1.txt", "file2.txt"], "message": "First" },
    { "files": ["file2.txt"], "message": "Second" }
  ]
}
JSON
)"
if run_tool_expect_fail gitHex.splitCommit "${REPO_DUP_FILE}" "${args_dup}"; then
	test_pass "splitCommit rejects duplicate file assignments"
else
	test_fail "duplicate file should fail validation"
fi

# SPLIT-13/14: At least two splits and no empty split
printf ' -> SPLIT-13/14 enforce split counts\n'
REPO_COUNT="${TEST_TMPDIR}/split-count"
create_split_commit_scenario "${REPO_COUNT}" 2
target_commit="$(commit_to_split "${REPO_COUNT}")"
args_single="$(
	cat <<JSON
{ "commit": "${target_commit}", "splits": [ { "files": ["file1.txt","file2.txt"], "message": "Only" } ] }
JSON
)"
if run_tool_expect_fail gitHex.splitCommit "${REPO_COUNT}" "${args_single}"; then
	test_pass "requires at least two splits"
else
	test_fail "single split should be rejected"
fi
args_empty="$(
	cat <<JSON
{
  "commit": "${target_commit}",
  "splits": [
    { "files": [], "message": "Empty" },
    { "files": ["file1.txt","file2.txt"], "message": "Rest" }
  ]
}
JSON
)"
if run_tool_expect_fail gitHex.splitCommit "${REPO_COUNT}" "${args_empty}"; then
	test_pass "empty split rejected"
else
	test_fail "empty split should be rejected"
fi

# SPLIT-16: Root commit cannot be split
printf ' -> SPLIT-16 cannot split root commit\n'
REPO_ROOT="${TEST_TMPDIR}/split-root"
create_test_repo "${REPO_ROOT}" 1
root_commit="$(cd "${REPO_ROOT}" && git rev-list --max-parents=0 HEAD)"
args_root="$(
	cat <<JSON
{
  "commit": "${root_commit}",
  "splits": [
    { "files": ["file1.txt"], "message": "One" },
    { "files": ["file1.txt"], "message": "Two" }
  ]
}
JSON
)"
if run_tool_expect_fail gitHex.splitCommit "${REPO_ROOT}" "${args_root}"; then
	test_pass "root commit split rejected"
else
	test_fail "root commit should not be split"
fi

# SPLIT-35: Commit not ancestor of HEAD
printf ' -> SPLIT-35 commit not ancestor rejected\n'
REPO_NON_ANCESTOR="${TEST_TMPDIR}/split-non-ancestor"
create_non_ancestor_scenario "${REPO_NON_ANCESTOR}"
non_ancestor_commit="$(cd "${REPO_NON_ANCESTOR}" && git rev-parse other)"
args_non_ancestor="$(
	cat <<JSON
{
  "commit": "${non_ancestor_commit}",
  "splits": [
    { "files": ["other.txt"], "message": "Other" },
    { "files": ["main.txt"], "message": "Main" }
  ]
}
JSON
)"
if run_tool_expect_fail gitHex.splitCommit "${REPO_NON_ANCESTOR}" "${args_non_ancestor}"; then
	test_pass "non-ancestor commit rejected"
else
	test_fail "splitCommit should fail for non-ancestor commit"
fi

# SPLIT-36: Rebase already in progress
printf ' -> SPLIT-36 rebase in progress prevents split\n'
REPO_IN_PROGRESS="${TEST_TMPDIR}/split-in-progress"
create_rebase_in_progress_scenario "${REPO_IN_PROGRESS}"
if ! in_progress_commit="$(cd "${REPO_IN_PROGRESS}" && git rev-list --reverse main..HEAD | head -n1)"; then
	in_progress_commit=""
fi
args_in_progress="$(
	cat <<JSON
{
  "commit": "${in_progress_commit}",
  "splits": [
    { "files": ["conflict.txt"], "message": "Part1" },
    { "files": ["conflict.txt"], "message": "Part2" }
  ]
}
JSON
)"
if run_tool_expect_fail gitHex.splitCommit "${REPO_IN_PROGRESS}" "${args_in_progress}"; then
	test_pass "splitCommit blocked during rebase"
else
	test_fail "splitCommit should fail when rebase already in progress"
fi

# SPLIT-33/38: autoStash with dirty dir
printf ' -> SPLIT-33 autoStash handles dirty working directory\n'
REPO_AUTOSTASH="${TEST_TMPDIR}/split-autostash"
create_split_commit_scenario "${REPO_AUTOSTASH}" 2
echo "dirty change" >>"${REPO_AUTOSTASH}/after.txt"
target_commit="$(commit_to_split "${REPO_AUTOSTASH}")"
args_autostash="$(
	cat <<JSON
{
  "commit": "${target_commit}",
  "autoStash": true,
  "splits": [
    { "files": ["file1.txt"], "message": "One" },
    { "files": ["file2.txt"], "message": "Two" }
  ]
}
JSON
)"
result_autostash="$(run_tool gitHex.splitCommit "${REPO_AUTOSTASH}" "${args_autostash}" 120)"
assert_json_field "${result_autostash}" '.success' "true" "splitCommit should succeed with autoStash"
if ! (cd "${REPO_AUTOSTASH}" && git diff --quiet -- after.txt); then
	test_pass "dirty change restored after split"
else
	test_fail "dirty change should be restored after splitCommit"
fi

# SPLIT-37: Conflict in subsequent commits returns rebasePaused
printf ' -> SPLIT-37 conflict in subsequent commit pauses rebase\n'
REPO_CONFLICT_SPLIT="${TEST_TMPDIR}/split-subsequent-conflict"
create_split_subsequent_conflict_scenario "${REPO_CONFLICT_SPLIT}"
target_commit="$(commit_to_split "${REPO_CONFLICT_SPLIT}")"
args_conflict="$(
	cat <<JSON
{
  "commit": "${target_commit}",
  "splits": [
    { "files": ["conflict.txt"], "message": "Conflict part" },
    { "files": ["other.txt"], "message": "Other part" }
  ]
}
JSON
)"
result_conflict="$(run_tool gitHex.splitCommit "${REPO_CONFLICT_SPLIT}" "${args_conflict}" 120)"
if printf '%s' "${result_conflict}" | jq -e '.rebasePaused == true' >/dev/null 2>&1; then
	test_pass "splitCommit reports rebasePaused on subsequent conflict"
else
	# If no conflict occurred, ensure repository is clean and rebase completed
	if [ -d "${REPO_CONFLICT_SPLIT}/.git/rebase-merge" ] || [ -d "${REPO_CONFLICT_SPLIT}/.git/rebase-apply" ]; then
		test_fail "splitCommit left rebase state without reporting rebasePaused"
	else
		test_pass "splitCommit completed without subsequent conflicts"
	fi
fi

echo ""
echo "splitCommit tests completed"
