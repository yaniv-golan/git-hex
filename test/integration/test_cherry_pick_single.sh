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
backup_ref="$(printf '%s' "${result}" | jq -r '.backupRef // empty')"
assert_contains "${backup_ref}" "git-hex/backup/" "backupRef should be returned"

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
backup_ref="$(printf '%s' "${result}" | jq -r '.backupRef // empty')"
assert_contains "${backup_ref}" "git-hex/backup/" "backupRef should be returned"

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

# ============================================================
# TEST: cherry-pick-single rejects merge commits (requires -m)
# ============================================================
printf ' -> cherry-pick-single rejects merge commits\n'

REPO_MERGE_COMMIT="${TEST_TMPDIR}/pick-merge-commit"
mkdir -p "${REPO_MERGE_COMMIT}"
tmp_merge_hash="$(mktemp "${TEST_TMPDIR}/merge_hash.XXXXXX")"
(
	cd "${REPO_MERGE_COMMIT}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "base" >base.txt
	git add base.txt && git commit -m "Base" >/dev/null

	git checkout -b feature >/dev/null 2>&1
	echo "feature" >feature.txt
	git add feature.txt && git commit -m "Feature" >/dev/null

	git checkout main >/dev/null 2>&1
	echo "main" >main.txt
	git add main.txt && git commit -m "Main" >/dev/null

	git merge --no-ff feature -m "Merge feature" >/dev/null 2>&1
	merge_hash="$(git rev-parse HEAD)"
	echo "${merge_hash}" >"${tmp_merge_hash}"
)

merge_hash="$(cat "${tmp_merge_hash}")"
rm -f "${tmp_merge_hash}"

run_tool_expect_fail_message_contains \
	git-hex-cherryPickSingle \
	"${REPO_MERGE_COMMIT}" \
	"{\"commit\": \"${merge_hash}\"}" \
	"merge commits" \
	"cherryPickSingle should reject merge commits with a helpful message"
test_pass "cherry-pick-single rejects merge commits"

# ============================================================
# TEST: cherry-pick-single handles empty commit (already applied)
# ============================================================
printf ' -> cherry-pick-single handles empty commit (changes already exist)\n'

REPO8="${TEST_TMPDIR}/pick-empty-commit"
mkdir -p "${REPO8}"
tmp_cherry_hash8="$(mktemp "${TEST_TMPDIR}/cherry_hash8.XXXXXX")"
(
	cd "${REPO8}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "base" >base.txt
	git add base.txt && git commit -m "Base commit" >/dev/null

	# Create a branch with a change
	git checkout -b source >/dev/null 2>&1
	echo "change" >change.txt
	git add change.txt && git commit -m "Add change" >/dev/null
	cherry_hash="$(git rev-parse HEAD)"

	# Go back to main and make the SAME change (so cherry-pick would be empty)
	git checkout main >/dev/null 2>&1
	echo "change" >change.txt
	git add change.txt && git commit -m "Same change on main" >/dev/null

	echo "${cherry_hash}" >"${tmp_cherry_hash8}"
)

cherry_hash8="$(cat "${tmp_cherry_hash8}")"
rm -f "${tmp_cherry_hash8}"

# This cherry-pick would result in an empty commit (changes already exist)
if run_tool_expect_fail git-hex-cherryPickSingle "${REPO8}" "{\"commit\": \"${cherry_hash8}\"}"; then
	# Should fail gracefully with a meaningful error
	test_pass "cherry-pick-single fails gracefully on empty commit"
else
	# If it succeeds, check that repo is clean (didn't leave in bad state)
	if [ ! -f "${REPO8}/.git/CHERRY_PICK_HEAD" ]; then
		test_pass "cherry-pick-single handled empty commit (possibly created empty commit)"
	else
		test_fail "should not leave repo in cherry-pick state"
	fi
fi

# ============================================================
# TEST: cherry-pick-single with abortOnConflict=false pauses on conflict
# ============================================================
printf ' -> cherry-pick-single with abortOnConflict=false pauses\n'

REPO9="${TEST_TMPDIR}/pick-pause"
mkdir -p "${REPO9}"
tmp_cherry_hash9="$(mktemp "${TEST_TMPDIR}/cherry_hash9.XXXXXX")"
(
	cd "${REPO9}"
	git init --initial-branch=main >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test"
	git config commit.gpgsign false

	echo "original" >conflict.txt
	git add conflict.txt && git commit -m "Base" >/dev/null

	git checkout -b source >/dev/null 2>&1
	echo "source change" >conflict.txt
	git add conflict.txt && git commit -m "Source" >/dev/null
	cherry_hash="$(git rev-parse HEAD)"

	git checkout main >/dev/null 2>&1
	echo "main change" >conflict.txt
	git add conflict.txt && git commit -m "Main" >/dev/null

	echo "${cherry_hash}" >"${tmp_cherry_hash9}"
)

cherry_hash9="$(cat "${tmp_cherry_hash9}")"
rm -f "${tmp_cherry_hash9}"

result9="$(run_tool git-hex-cherryPickSingle "${REPO9}" "{\"commit\": \"${cherry_hash9}\", \"abortOnConflict\": false}")" || true
paused_val="$(printf '%s' "${result9}" | jq -r '.paused // empty')"
if [ "${paused_val}" = "true" ]; then
	commit_msg="$(printf '%s' "${result9}" | jq -r '.commitMessage // empty')"
	if [ -z "${commit_msg}" ]; then
		test_fail "paused cherry-pick should include commitMessage"
	fi
	stash_not_restored="$(printf '%s' "${result9}" | jq -r 'if has("stashNotRestored") then (.stashNotRestored | tostring) else "" end')"
	assert_eq "false" "${stash_not_restored}" "paused cherry-pick should include stashNotRestored=false"
	# Verify repo is in cherry-pick state
	if [ -f "${REPO9}/.git/CHERRY_PICK_HEAD" ]; then
		test_pass "cherry-pick-single pauses on conflict with abortOnConflict=false"
	else
		test_fail "should be in cherry-pick state when paused"
	fi
else
	test_fail "should return paused=true when abortOnConflict=false and conflict occurs"
fi

echo ""
echo "All git-hex-cherryPickSingle tests passed!"
