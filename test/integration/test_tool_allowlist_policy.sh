#!/usr/bin/env bash
# Integration tests: server.d/policy.sh keeps the framework's tool allowlist
# and does not change the server's shell options.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=../common/env.sh disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"
# shellcheck source=../common/git_fixtures.sh disable=SC1091
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_verify_framework
test_create_tmpdir

echo "=== Testing tool allowlist enforcement with server.d/policy.sh ==="

# ============================================================
# TEST: a tool missing from MCPBASH_TOOL_ALLOWLIST is denied
# ============================================================
printf ' -> tool outside MCPBASH_TOOL_ALLOWLIST is denied\n'

REPO="${TEST_TMPDIR}/allowlist-deny"
create_test_repo "${REPO}" 3

saved_allowlist="${MCPBASH_TOOL_ALLOWLIST}"
export MCPBASH_TOOL_ALLOWLIST="git-hex-getConflictStatus"
if run_tool_expect_fail git-hex-getRebasePlan "${REPO}" '{"count": 3}'; then
	test_pass "tool outside the allowlist is denied"
else
	test_fail "git-hex-getRebasePlan ran although it is not in MCPBASH_TOOL_ALLOWLIST"
fi

# ============================================================
# TEST: a tool in MCPBASH_TOOL_ALLOWLIST still runs
# ============================================================
printf ' -> tool in MCPBASH_TOOL_ALLOWLIST runs\n'

export MCPBASH_TOOL_ALLOWLIST="git-hex-getRebasePlan"
run_tool git-hex-getRebasePlan "${REPO}" '{"count": 3}' >/dev/null
test_pass "allowlisted tool runs"
export MCPBASH_TOOL_ALLOWLIST="${saved_allowlist}"

# ============================================================
# TEST: sourcing policy.sh leaves the caller's shell options alone
# ============================================================
printf ' -> sourcing policy.sh does not change shell options\n'

opts="$(bash -c 'set +euo pipefail; before="$-:$(set -o | grep pipefail)"; . "$1"; after="$-:$(set -o | grep pipefail)"; [ "${before}" = "${after}" ] && echo same || echo "changed: ${before} -> ${after}"' _ "${MCPBASH_PROJECT_ROOT}/server.d/policy.sh")"
if [ "${opts}" = "same" ]; then
	test_pass "policy.sh does not change shell options"
else
	test_fail "policy.sh changed the server's shell options (${opts})"
fi

echo ""
echo "All allowlist policy tests passed!"
