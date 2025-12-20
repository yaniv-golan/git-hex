#!/usr/bin/env bash
# High-value adversarial/uncommon scenarios
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

echo "=== High-Value Adversarial Tests ==="

is_windows() {
	case "$(uname -s 2>/dev/null || printf '')" in
	MINGW* | MSYS* | CYGWIN*) return 0 ;;
	esac
	return 1
}

# HV-01: Worktree repoPath works for mutating tools (worktree has separate gitdir)
printf ' -> HV-01 worktree support (createFixup)\n'
REPO_WT="${TEST_TMPDIR}/worktree-base"
create_staged_changes_repo "${REPO_WT}"
WORKTREE_DIR="${TEST_TMPDIR}/worktree-dir"
(
	cd "${REPO_WT}"
	git checkout -b wt-branch >/dev/null 2>&1
	git worktree add "${WORKTREE_DIR}" -b wt-worktree >/dev/null 2>&1
)
(
	cd "${WORKTREE_DIR}"
	# Stage a tracked change in the worktree
	echo "modified" >file.txt
	git add file.txt
)
target_hash="$(cd "${WORKTREE_DIR}" && git rev-parse HEAD)"
wt_result="$(run_tool git-hex-createFixup "${WORKTREE_DIR}" "{\"commit\":\"${target_hash}\"}")"
assert_json_field "${wt_result}" '.success' "true" "createFixup should succeed in worktree"
wt_backup_ref="$(printf '%s' "${wt_result}" | jq -r '.backupRef // empty')"
assert_contains "${wt_backup_ref}" "git-hex/backup/" "backupRef should be returned in worktree"
test_pass "worktree repoPath works"

# HV-02: Shallow clone yields a helpful error on missing onto
printf ' -> HV-02 shallow clone invalid onto includes hint\n'
REPO_FULL="${TEST_TMPDIR}/shallow-full"
create_test_repo "${REPO_FULL}" 6
REPO_SHALLOW="${TEST_TMPDIR}/shallow-clone"
git clone --depth 1 "file://${REPO_FULL}" "${REPO_SHALLOW}" >/dev/null 2>&1
run_tool_expect_fail_message_contains \
	git-hex-rebaseWithPlan \
	"${REPO_SHALLOW}" \
	'{"onto":"HEAD~3","plan":[]}' \
	"unshallow" \
	"shallow clone should mention unshallow when onto is missing"
test_pass "shallow clone hint present"

# HV-03: rebase-apply backend exposes conflicting commit in getConflictStatus
printf ' -> HV-03 rebase-apply conflictingCommit extracted\n'
REPO_APPLY="${TEST_TMPDIR}/rebase-apply-conflict"
create_conflict_scenario "${REPO_APPLY}"
(
	cd "${REPO_APPLY}"
	# Ensure we're on feature branch (create_conflict_scenario ends on feature)
	# Force apply backend so .git/rebase-apply is used.
	git rebase --apply main >/dev/null 2>&1 || true
)
conflict_status="$(run_tool git-hex-getConflictStatus "${REPO_APPLY}" '{"includeContent": false}')"
assert_json_field "${conflict_status}" '.inConflict' "true" "repo should be in conflict"
assert_json_field "${conflict_status}" '.conflictType' "rebase" "conflictType should be rebase"
conflicting_commit="$(printf '%s' "${conflict_status}" | jq -r '.conflictingCommit // empty')"
if [ -z "${conflicting_commit}" ] || [ "${conflicting_commit}" = "null" ]; then
	test_fail "conflictingCommit should be present in rebase-apply mode"
fi
test_pass "rebase-apply conflictingCommit present"
(cd "${REPO_APPLY}" && git rebase --abort >/dev/null 2>&1) || true

# HV-04: index.lock causes a clean tool failure (no partial success)
printf ' -> HV-04 index.lock causes tool failure\n'
REPO_LOCK="${TEST_TMPDIR}/index-lock"
create_staged_changes_repo "${REPO_LOCK}"
(
	cd "${REPO_LOCK}"
	# Ensure staged changes so createFixup would otherwise proceed.
	echo "modified" >file.txt
	git add file.txt
	# Create index lock
	: >.git/index.lock
)
if run_tool_expect_fail git-hex-createFixup "${REPO_LOCK}" '{"commit":"HEAD"}'; then
	test_pass "createFixup fails with index.lock present"
else
	test_fail "createFixup should fail with index.lock present"
fi
rm -f "${REPO_LOCK}/.git/index.lock" 2>/dev/null || true

# HV-05: failing pre-commit hook surfaces as a hook error (skip on Windows)
printf ' -> HV-05 failing pre-commit hook surfaces\n'
if is_windows; then
	test_pass "hook test skipped on Windows"
else
	REPO_HOOK="${TEST_TMPDIR}/hook-fail"
	create_staged_changes_repo "${REPO_HOOK}"
	(
		cd "${REPO_HOOK}"
		mkdir -p .githooks
		cat >.githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
echo "pre-commit: reject" >&2
exit 1
EOF
		chmod +x .githooks/pre-commit
		git config core.hooksPath .githooks
		echo "modified" >file.txt
		git add file.txt
	)
	run_tool_expect_fail_message_contains \
		git-hex-createFixup \
		"${REPO_HOOK}" \
		'{"commit":"HEAD"}' \
		"hook" \
		"createFixup should surface hook failures"
	test_pass "hook failure surfaced"
fi

echo ""
echo "High-value adversarial tests completed"
