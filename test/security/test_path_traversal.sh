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

echo ""
echo "All security tests passed!"
