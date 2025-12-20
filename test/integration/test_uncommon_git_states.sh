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

if run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_REVERT}" '{"onto":"HEAD~1","plan":[]}'; then
	test_pass "mutating tools blocked during revert"
else
	test_fail "tools should fail during revert"
fi
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

if run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_BISECT}" '{"onto":"HEAD~1","plan":[]}'; then
	test_pass "mutating tools blocked during bisect"
else
	test_fail "tools should fail during bisect"
fi
(cd "${REPO_BISECT}" && git bisect reset >/dev/null 2>&1) || true

echo ""
echo "Uncommon git state tests completed"
