#!/usr/bin/env bash
# Security tests for path traversal/injection
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

echo "=== Security: Path Injection ==="

# Prepare repo with conflict so resolveConflict is applicable
REPO_PATH_SEC="${TEST_TMPDIR}/sec-path"
create_conflict_scenario "${REPO_PATH_SEC}"
if ! (cd "${REPO_PATH_SEC}" && git rebase main >/dev/null 2>&1); then
	:
fi

# SEC-10: Path traversal rejected
printf ' -> SEC-10 path traversal rejected\n'
if run_tool_expect_fail gitHex.resolveConflict "${REPO_PATH_SEC}" '{"file": "../../../etc/passwd"}'; then
	test_pass "path traversal blocked"
else
	test_fail "path traversal should be rejected"
fi

# SEC-11: Absolute path rejected
printf ' -> SEC-11 absolute path rejected\n'
if run_tool_expect_fail gitHex.resolveConflict "${REPO_PATH_SEC}" '{"file": "/etc/passwd"}'; then
	test_pass "absolute path blocked"
else
	test_fail "absolute paths should be rejected"
fi

# SEC-12: Null byte in path rejected
printf ' -> SEC-12 null byte in path rejected\n'
null_path=$'a\0b'
encoded_path="$(printf '%s' "${null_path}" | jq -Rs '.')"
if run_tool_expect_fail gitHex.resolveConflict "${REPO_PATH_SEC}" "{\"file\": ${encoded_path}}"; then
	test_pass "null byte in path rejected"
else
	test_fail "null byte path should be rejected"
fi

echo ""
echo "Path injection security tests completed"
