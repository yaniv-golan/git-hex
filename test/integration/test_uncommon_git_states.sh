#!/usr/bin/env bash
# Integration tests for uncommon git states (bare repo, revert, bisect)
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

echo "=== Uncommon Git State Tests ==="

assert_mutating_tools_blocked() {
	local repo_path="$1"
	local keyword="$2"
	local label="$3"

	run_tool_expect_fail_message_contains \
		git-hex-rebaseWithPlan \
		"${repo_path}" \
		'{"onto":"HEAD~1","plan":[]}' \
		"${keyword}" \
		"${label}: rebaseWithPlan should be blocked"
	run_tool_expect_fail_message_contains \
		git-hex-amendLastCommit \
		"${repo_path}" \
		'{"message":"test"}' \
		"${keyword}" \
		"${label}: amendLastCommit should be blocked"
	run_tool_expect_fail_message_contains \
		git-hex-createFixup \
		"${repo_path}" \
		'{"commit":"HEAD"}' \
		"${keyword}" \
		"${label}: createFixup should be blocked"
	run_tool_expect_fail_message_contains \
		git-hex-undoLast \
		"${repo_path}" \
		'{}' \
		"${keyword}" \
		"${label}: undoLast should be blocked"

	# splitCommit parses inputs before checking operation state; provide minimal valid args to reach the guard.
	args_split_block='{"commit":"HEAD","splits":[{"files":["a"],"message":"A"},{"files":["b"],"message":"B"}]}'
	run_tool_expect_fail_message_contains \
		git-hex-splitCommit \
		"${repo_path}" \
		"${args_split_block}" \
		"${keyword}" \
		"${label}: splitCommit should be blocked"
}

# STATE-01: Bare repositories rejected early
printf ' -> STATE-01 bare repositories are rejected\n'
BARE_REPO="${TEST_TMPDIR}/bare-repo"
mkdir -p "${BARE_REPO}"
(cd "${BARE_REPO}" && git init --bare >/dev/null 2>&1)
if run_tool_expect_fail git-hex-getRebasePlan "${BARE_REPO}" '{"count": 1}'; then
	test_pass "bare repositories rejected"
else
	test_fail "bare repositories should be rejected"
fi

# STATE-02: Paused revert blocks mutating tools
printf ' -> STATE-02 paused revert blocks mutating tools\n'
REPO_REVERT="${TEST_TMPDIR}/paused-revert"
mkdir -p "${REPO_REVERT}"
(
	cd "${REPO_REVERT}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	printf 'one\n' >conflict.txt
	git add conflict.txt && git commit -m "Base" >/dev/null

	printf 'two\n' >conflict.txt
	git add conflict.txt && git commit -m "Change 1" >/dev/null
	commit_to_revert="$(git rev-parse HEAD)"

	printf 'three\n' >conflict.txt
	git add conflict.txt && git commit -m "Change 2" >/dev/null

	# This revert should conflict because the file has moved on since Change 1.
	git revert "${commit_to_revert}" >/dev/null 2>&1 || true
	if [ ! -f ".git/REVERT_HEAD" ]; then
		echo "WARNING: expected REVERT_HEAD not found; test fixture did not enter paused revert state" >&2
		exit 1
	fi
)

printf '    - getConflictStatus detects revert conflicts\n'
revert_status="$(run_tool git-hex-getConflictStatus "${REPO_REVERT}" '{"includeContent": false}')"
assert_json_field "${revert_status}" '.inConflict' "true" "should detect conflict"
assert_json_field "${revert_status}" '.conflictType' "revert" "should report revert conflictType"
test_pass "getConflictStatus detects revert"

assert_mutating_tools_blocked "${REPO_REVERT}" "revert" "revert"
(cd "${REPO_REVERT}" && git revert --abort >/dev/null 2>&1) || true

# STATE-03: Bisect blocks mutating tools
printf ' -> STATE-03 bisect blocks mutating tools\n'
REPO_BISECT="${TEST_TMPDIR}/bisect"
create_test_repo "${REPO_BISECT}" 4
(
	cd "${REPO_BISECT}"
	# Start a bisect session (leaves .git/BISECT_* markers).
	git bisect start >/dev/null 2>&1
	git bisect bad HEAD >/dev/null 2>&1
	git bisect good HEAD~3 >/dev/null 2>&1
	if [ ! -f ".git/BISECT_LOG" ] && [ ! -f ".git/BISECT_START" ]; then
		echo "WARNING: expected bisect markers not found" >&2
		exit 1
	fi
)

assert_mutating_tools_blocked "${REPO_BISECT}" "bisect" "bisect"
(cd "${REPO_BISECT}" && git bisect reset >/dev/null 2>&1) || true

# STATE-04: Paused cherry-pick blocks mutating tools
printf ' -> STATE-04 paused cherry-pick blocks mutating tools\n'
REPO_CHERRY_PICK="${TEST_TMPDIR}/paused-cherry-pick"
create_conflict_scenario "${REPO_CHERRY_PICK}"
(
	cd "${REPO_CHERRY_PICK}"
	main_tip="$(git rev-parse main)"
	git cherry-pick "${main_tip}" >/dev/null 2>&1 || true
	if [ ! -f ".git/CHERRY_PICK_HEAD" ]; then
		echo "WARNING: expected CHERRY_PICK_HEAD not found; test fixture did not enter paused cherry-pick state" >&2
		exit 1
	fi
)
cherry_status="$(run_tool git-hex-getConflictStatus "${REPO_CHERRY_PICK}" '{"includeContent": false}')"
assert_json_field "${cherry_status}" '.inConflict' "true" "should detect conflict"
assert_json_field "${cherry_status}" '.conflictType' "cherry-pick" "should report cherry-pick conflictType"
test_pass "getConflictStatus detects cherry-pick"
assert_mutating_tools_blocked "${REPO_CHERRY_PICK}" "cherry-pick" "cherry-pick"
(cd "${REPO_CHERRY_PICK}" && git cherry-pick --abort >/dev/null 2>&1) || true

# STATE-05: Paused merge blocks mutating tools
printf ' -> STATE-05 paused merge blocks mutating tools\n'
REPO_MERGE="${TEST_TMPDIR}/paused-merge"
create_conflict_scenario "${REPO_MERGE}"
(
	cd "${REPO_MERGE}"
	git merge main >/dev/null 2>&1 || true
	if [ ! -f ".git/MERGE_HEAD" ]; then
		echo "WARNING: expected MERGE_HEAD not found; test fixture did not enter paused merge state" >&2
		exit 1
	fi
)
merge_status="$(run_tool git-hex-getConflictStatus "${REPO_MERGE}" '{"includeContent": false}')"
assert_json_field "${merge_status}" '.inConflict' "true" "should detect conflict"
assert_json_field "${merge_status}" '.conflictType' "merge" "should report merge conflictType"
test_pass "getConflictStatus detects merge"
assert_mutating_tools_blocked "${REPO_MERGE}" "merge" "merge"
(cd "${REPO_MERGE}" && git merge --abort >/dev/null 2>&1) || true

echo ""
echo "Uncommon git state tests completed"
