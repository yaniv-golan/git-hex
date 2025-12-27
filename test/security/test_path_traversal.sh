#!/usr/bin/env bash
# Security tests for path traversal prevention
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

echo "=== Security Tests: Path Traversal Prevention ==="

# Source helpers for direct path-validation regression checks
# shellcheck source=../../lib/git-helpers.sh disable=SC1091
. "${SCRIPT_DIR}/../../lib/git-helpers.sh"

# ============================================================
# SECURITY: Path traversal attempts should be blocked
# ============================================================
printf ' -> blocks path traversal via repoPath\n'

ALLOWED_ROOT="${TEST_TMPDIR}/allowed"
FORBIDDEN_ROOT="${TEST_TMPDIR}/forbidden"

mkdir -p "${ALLOWED_ROOT}"
create_test_repo "${FORBIDDEN_ROOT}" 1

# Try to access forbidden repo via traversal
if run_tool_expect_fail git-hex-getRebasePlan "${ALLOWED_ROOT}" "{\"repoPath\": \"${ALLOWED_ROOT}/../forbidden\"}"; then
	test_pass "blocks path traversal via repoPath"
else
	test_fail "should block path traversal"
fi

# ============================================================
# SECURITY: Absolute path outside roots should be blocked
# ============================================================
printf ' -> blocks absolute path outside roots\n'

if run_tool_expect_fail git-hex-getRebasePlan "${ALLOWED_ROOT}" "{\"repoPath\": \"${FORBIDDEN_ROOT}\"}"; then
	test_pass "blocks absolute path outside roots"
else
	test_fail "should block absolute path outside roots"
fi

# ============================================================
# SECURITY: Symlink traversal should be blocked
# ============================================================
printf ' -> blocks symlink traversal\n'

# Create symlink from allowed to forbidden
if ln -sf "${FORBIDDEN_ROOT}" "${ALLOWED_ROOT}/link_to_forbidden" 2>/dev/null; then
	if run_tool_expect_fail git-hex-getRebasePlan "${ALLOWED_ROOT}" "{\"repoPath\": \"${ALLOWED_ROOT}/link_to_forbidden\"}"; then
		test_pass "blocks symlink traversal"
	else
		test_fail "should block symlink traversal"
	fi
else
	echo "  (skipping symlink test - symlinks not supported)"
	test_pass "symlink test skipped"
fi

# ============================================================
# SECURITY: File path traversal in resolveConflict
# ============================================================
printf ' -> blocks file path traversal patterns in resolveConflict\n'

REPO_FILE_TRAVERSAL="${TEST_TMPDIR}/file-traversal"
create_paused_rebase_scenario "${REPO_FILE_TRAVERSAL}"

# Test various path traversal patterns
traversal_patterns=(
	"../etc/passwd"
	".."
	"foo/../../../etc/passwd"
	"foo/bar/../../../etc/passwd"
	"some/path/.." # Path ending with /.. (the missing pattern from audit)
	"dir/subdir/file/.." # Another path ending with /..
)

for pattern in "${traversal_patterns[@]}"; do # bash32-safe: traversal_patterns hardcoded non-empty above
	if run_tool_expect_fail git-hex-resolveConflict "${REPO_FILE_TRAVERSAL}" "{\"file\": \"${pattern}\"}"; then
		printf '   [PASS] blocked: %s\n' "${pattern}"
	else
		test_fail "should block path traversal pattern: ${pattern}"
	fi
done
test_pass  "blocks file path traversal patterns"

# Regression: filenames that start with ".." are allowed as long as they aren't traversal segments.
# This should be allowed: it's not "../" and does not contain a "/../" segment or end with "/..".
if  git_hex_is_safe_repo_relative_path "dir/..backup"; then
	test_pass "allows non-traversal '..' filename segment"
else
	test_fail "should allow filenames like dir/..backup"
fi

# ============================================================
# SECURITY: File path traversal in getConflictStatus
# ============================================================
printf ' -> blocks file path traversal patterns in getConflictStatus filter\n'

# getConflictStatus doesn't take a file parameter directly, but let's ensure
# the path validation function works correctly for internal use

# Test absolute path rejection
if run_tool_expect_fail git-hex-resolveConflict "${REPO_FILE_TRAVERSAL}" '{"file": "/etc/passwd"}'; then
	test_pass "blocks absolute path in file parameter"
else
	test_fail "should block absolute path"
fi

# Test Windows drive letter path rejection
if run_tool_expect_fail git-hex-resolveConflict "${REPO_FILE_TRAVERSAL}" '{"file": "C:\\Windows\\System32"}'; then
	test_pass "blocks Windows drive letter path"
else
	test_fail "should block Windows drive letter path"
fi

echo ""
echo "All security tests passed!"
