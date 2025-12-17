#!/usr/bin/env bash
# Integration tests for git-hex-cherryPickSingle
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

echo "=== Testing git-hex-cherryPickSingle ==="

# ============================================================
# TEST: cherry-pick-single succeeds with clean pick
# ============================================================
printf ' -> cherry-pick-single succeeds with clean pick\n'

REPO="${TEST_TMPDIR}/pick-clean"
mkdir -p "${REPO}"
tmp_cherry_hash="$(mktemp "${TEST_TMPDIR}/cherry_hash.XXXXXX")"
(
	cd "${REPO}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "base" >base.txt
	git add base.txt && git commit -m "Base commit" >/dev/null

	# Create a branch with a commit to cherry-pick
	git checkout -b source >/dev/null 2>&1
	echo "cherry" >cherry.txt
	git add cherry.txt && git commit -m "Cherry commit" >/dev/null
	cherry_hash="$(git rev-parse HEAD)"

	# Go back to main
	git checkout main >/dev/null 2>&1

	echo "${cherry_hash}" >"${tmp_cherry_hash}"
)

cherry_hash="$(cat "${tmp_cherry_hash}")"
rm -f "${tmp_cherry_hash}"

before_count="$(cd "${REPO}" && git rev-list --count HEAD)"

result="$(run_tool git-hex-cherryPickSingle "${REPO}" "{\"commit\": \"${cherry_hash}\"}")"

assert_json_fields_eq "${result}" '.success' "true" '.sourceCommit' "${cherry_hash}"

after_count="$(cd "${REPO}" && git rev-list --count HEAD)"
assert_eq "$((before_count + 1))" "${after_count}" "should have one more commit"

# Verify the file was cherry-picked
assert_file_exists "${REPO}/cherry.txt" "cherry-picked file should exist"

test_pass "cherry-pick-single succeeds with clean pick"

# ============================================================
# TEST: cherry-pick-single with noCommit flag
# ============================================================
printf ' -> cherry-pick-single with noCommit applies without committing\n'

REPO2="${TEST_TMPDIR}/pick-nocommit"
mkdir -p "${REPO2}"
tmp_cherry_hash2="$(mktemp "${TEST_TMPDIR}/cherry_hash2.XXXXXX")"
(
	cd "${REPO2}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "base" >base.txt
	git add base.txt && git commit -m "Base commit" >/dev/null

	git checkout -b source >/dev/null 2>&1
	echo "nocommit" >nocommit.txt
	git add nocommit.txt && git commit -m "NoCommit source" >/dev/null
	cherry_hash="$(git rev-parse HEAD)"

	git checkout main >/dev/null 2>&1

	echo "${cherry_hash}" >"${tmp_cherry_hash2}"
)

cherry_hash="$(cat "${tmp_cherry_hash2}")"
rm -f "${tmp_cherry_hash2}"

before_count="$(cd "${REPO2}" && git rev-list --count HEAD)"

result="$(run_tool git-hex-cherryPickSingle "${REPO2}" "{\"commit\": \"${cherry_hash}\", \"noCommit\": true}")"

assert_json_field "${result}" '.success' "true" "cherry-pick should succeed"

after_count="$(cd "${REPO2}" && git rev-list --count HEAD)"
assert_eq "${before_count}" "${after_count}" "commit count should be unchanged with noCommit"

# Verify the file exists but is staged
assert_file_exists "${REPO2}/nocommit.txt" "cherry-picked file should exist"
staged="$(cd "${REPO2}" && git diff --cached --name-only)"
assert_contains "${staged}" "nocommit.txt" "file should be staged"

test_pass "cherry-pick-single with noCommit applies without committing"

# ============================================================
# TEST: cherry-pick-single aborts on conflict
# ============================================================
printf ' -> cherry-pick-single aborts on conflict and restores state\n'

REPO3="${TEST_TMPDIR}/pick-conflict"
mkdir -p "${REPO3}"
tmp_cherry_hash3="$(mktemp "${TEST_TMPDIR}/cherry_hash3.XXXXXX")"
(
	cd "${REPO3}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "original" >conflict.txt
	git add conflict.txt && git commit -m "Base commit" >/dev/null

	# Create conflicting commit on branch
	git checkout -b source >/dev/null 2>&1
	echo "source version" >conflict.txt
	git add conflict.txt && git commit -m "Source change" >/dev/null
	cherry_hash="$(git rev-parse HEAD)"

	# Make different change on main
	git checkout main >/dev/null 2>&1
	echo "main version" >conflict.txt
	git add conflict.txt && git commit -m "Main change" >/dev/null

	echo "${cherry_hash}" >"${tmp_cherry_hash3}"
)

cherry_hash="$(cat "${tmp_cherry_hash3}")"
rm -f "${tmp_cherry_hash3}"

before_head="$(cd "${REPO3}" && git rev-parse HEAD)"

if run_tool_expect_fail git-hex-cherryPickSingle "${REPO3}" "{\"commit\": \"${cherry_hash}\"}"; then
	# Verify repo is not in cherry-pick state
	if [ -f "${REPO3}/.git/CHERRY_PICK_HEAD" ]; then
		test_fail "repo should not be in cherry-pick state after abort"
	fi

	# Verify HEAD is restored
	after_head="$(cd "${REPO3}" && git rev-parse HEAD)"
	assert_eq "${before_head}" "${after_head}" "HEAD should be restored after abort"

	test_pass "cherry-pick-single aborts on conflict and restores state"
else
	test_fail "should fail on conflict"
fi

# ============================================================
# TEST: cherry-pick-single fails on dirty working directory
# ============================================================
printf ' -> cherry-pick-single fails on dirty working directory\n'

REPO4="${TEST_TMPDIR}/pick-dirty"
mkdir -p "${REPO4}"
tmp_cherry_hash4="$(mktemp "${TEST_TMPDIR}/cherry_hash4.XXXXXX")"
(
	cd "${REPO4}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "base" >base.txt
	git add base.txt && git commit -m "Base" >/dev/null

	git checkout -b source >/dev/null 2>&1
	echo "pick" >pick.txt
	git add pick.txt && git commit -m "Pick" >/dev/null
	cherry_hash="$(git rev-parse HEAD)"

	git checkout main >/dev/null 2>&1

	# Make dirty
	echo "dirty" >dirty.txt
	git add dirty.txt

	echo "${cherry_hash}" >"${tmp_cherry_hash4}"
)

cherry_hash="$(cat "${tmp_cherry_hash4}")"
rm -f "${tmp_cherry_hash4}"

if run_tool_expect_fail git-hex-cherryPickSingle "${REPO4}" "{\"commit\": \"${cherry_hash}\"}"; then
	test_pass "cherry-pick-single fails on dirty working directory"
else
	test_fail "should fail on dirty working directory"
fi

# ============================================================
# TEST: cherry-pick-single fails on invalid commit
# ============================================================
printf ' -> cherry-pick-single fails on invalid commit ref\n'

REPO5="${TEST_TMPDIR}/pick-invalid"
create_test_repo "${REPO5}" 2

if run_tool_expect_fail git-hex-cherryPickSingle "${REPO5}" '{"commit": "nonexistent123"}'; then
	test_pass "cherry-pick-single fails on invalid commit ref"
else
	test_fail "should fail on invalid commit ref"
fi

# ============================================================
# TEST: cherry-pick-single fails on empty repo
# ============================================================
printf ' -> cherry-pick-single fails on empty repo\n'

REPO6="${TEST_TMPDIR}/pick-empty"
mkdir -p "${REPO6}"
(cd "${REPO6}" && git init --initial-branch=main >/dev/null 2>&1 && git config user.email "test@example.com" && git config user.name "Test" && git config commit.gpgsign false)

if run_tool_expect_fail git-hex-cherryPickSingle "${REPO6}" '{"commit": "abc123"}'; then
	test_pass "cherry-pick-single fails on empty repo"
else
	test_fail "should fail on empty repo"
fi

# ============================================================
# TEST: cherry-pick-single fails on invalid strategy
# ============================================================
printf ' -> cherry-pick-single fails on invalid strategy\n'

REPO7="${TEST_TMPDIR}/pick-invalid-strategy"
create_test_repo "${REPO7}" 2

if run_tool_expect_fail git-hex-cherryPickSingle "${REPO7}" '{"commit": "HEAD", "strategy": "invalid-strategy"}'; then
	test_pass "cherry-pick-single fails on invalid strategy"
else
	test_fail "should fail on invalid strategy"
fi

echo ""
echo "All git-hex-cherryPickSingle tests passed!"
