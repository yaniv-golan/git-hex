#!/usr/bin/env bash
# Security tests for message injection and quoting
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

echo "=== Security: Message Injection ==="

REPO_SEC_MSG="${TEST_TMPDIR}/sec-message"
create_test_repo "${REPO_SEC_MSG}" 2

messages=("'; rm -rf /'" "\$(cat /etc/passwd)" "\`id\`" "\$HOME")
for msg in "${messages[@]}"; do
	target_commit="$(cd "${REPO_SEC_MSG}" && git rev-list --reverse HEAD~1..HEAD | tail -n1)"
	encoded_msg="$(printf '%s' "${msg}" | jq -Rs '.')"
	plan="[ {\"action\": \"reword\", \"commit\": \"${target_commit}\", \"message\": ${encoded_msg} } ]"
	result="$(run_tool git-hex-rebaseWithPlan "${REPO_SEC_MSG}" "{\"onto\": \"HEAD~1\", \"plan\": ${plan}, \"requireComplete\": true}")"
	assert_json_field "${result}" '.success' "true" "reword should succeed with special chars"
	latest_msg="$(cd "${REPO_SEC_MSG}" && git log -1 --format='%s')"
	assert_eq "${msg}" "${latest_msg}" "message should be preserved literally"
done
test_pass "special character messages preserved without execution"

# SEC-05: Null byte in message rejected
printf ' -> SEC-05 null byte in message rejected\n'
target_commit="$(cd "${REPO_SEC_MSG}" && git rev-list --reverse HEAD~1..HEAD | tail -n1)"
plan_null="[ {\"action\": \"reword\", \"commit\": \"${target_commit}\", \"message\": \"a\\u0000b\"} ]"
if run_tool_expect_fail git-hex-rebaseWithPlan "${REPO_SEC_MSG}" "{\"onto\": \"HEAD~1\", \"plan\": ${plan_null}, \"requireComplete\": true}"; then
	test_pass "message containing null byte rejected"
else
	test_fail "null byte in message should be rejected"
fi

echo ""
echo "Message injection security tests completed"
