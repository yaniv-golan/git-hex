#!/usr/bin/env bash
# Validate that MCP `completion/complete` and `resources/templates/list` work for git-hex,
# and that `resources/read` can read a permitted file URI under configured roots.
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

echo "=== MCP completions + resources tests ==="

REPO_ROOT="${TEST_TMPDIR}/mcp-capabilities-repo"
create_test_repo "${REPO_ROOT}" 1

# Create a predictable file under .git to read via resources/read.
mkdir -p "${REPO_ROOT}/.git/refs/git-hex/backup"
printf '%s' "deadbeef" >"${REPO_ROOT}/.git/refs/git-hex/backup/demo_backup"

req="${TEST_TMPDIR}/requests.ndjson"
resp="${TEST_TMPDIR}/responses.ndjson"

cat >"${req}" <<JSON
{"jsonrpc":"2.0","id":"init","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":"comp","method":"completion/complete","params":{"ref":{"type":"ref/prompt","name":"git-hex-ref"},"argument":{"name":"ref","value":"ma"},"context":{"arguments":{"repoPath":"${REPO_ROOT}"}},"limit":10}}
{"jsonrpc":"2.0","id":"rlist","method":"resources/list","params":{}}
{"jsonrpc":"2.0","id":"tmpl","method":"resources/templates/list","params":{}}
{"jsonrpc":"2.0","id":"read","method":"resources/read","params":{"uri":"file://${REPO_ROOT}/.git/refs/git-hex/backup/demo_backup"}}
JSON

# Run the server in stdio mode and capture responses.
MCPBASH_PROJECT_ROOT="${PROJECT_ROOT}" MCPBASH_ROOTS="${REPO_ROOT}" MCP_RESOURCES_ROOTS="${REPO_ROOT}" ./git-hex.sh <"${req}" >"${resp}"

if ! grep -q '"id":"comp"' "${resp}"; then
	test_fail "missing completion/complete response"
fi
if ! grep -q '"id":"tmpl"' "${resp}"; then
	test_fail "missing resources/templates/list response"
fi
if ! grep -q '"id":"rlist"' "${resp}"; then
	test_fail "missing resources/list response"
fi
if ! grep -q '"id":"read"' "${resp}"; then
	test_fail "missing resources/read response"
fi

# Validate completion results include main.
comp_line="$(grep '"id":"comp"' "${resp}" | head -n1)"
comp_values_len="$(printf '%s' "${comp_line}" | jq '.result.completion.values | length')"
if [ "${comp_values_len}" -lt 1 ]; then
	test_fail "expected at least one completion value"
fi
if ! printf '%s' "${comp_line}" | jq -e '.result.completion.values[] | if type == "object" then .text else . end | select(. == "main")' >/dev/null; then
	test_fail "expected completion values to include \"main\""
fi

# Validate resource templates list includes all git-hex templates.
tmpl_line="$( grep '"id":"tmpl"' "${resp}" | head -n1)"
tmpl_total="$( printf '%s' "${tmpl_line}" | jq -r '.result._meta["mcpbash/total"] // 0')"
assert_eq  "5" "${tmpl_total}" "expected 5 resource templates"
if  ! printf '%s' "${tmpl_line}" | jq -e '.result.resourceTemplates[].name | select(. == "git-hex-rebase-todo")' >/dev/null; then
	test_fail "expected resourceTemplates to include git-hex-rebase-todo"
fi

# Validate resources/list returns a well-formed response (git-hex currently has none).
rlist_line="$( grep '"id":"rlist"' "${resp}" | head -n1)"
rlist_total="$( printf '%s' "${rlist_line}" | jq -r '.result._meta["mcpbash/total"] // 0')"
assert_eq  "0" "${rlist_total}" "expected 0 resources"
if  ! printf '%s' "${rlist_line}" | jq -e '.result.resources | type == "array"' >/dev/null; then
	test_fail "expected resources to be an array"
fi

# Validate resources/read returns the file contents.
read_line="$( grep '"id":"read"' "${resp}" | head -n1)"
read_text="$( printf '%s' "${read_line}" | jq -r '.result.contents[0].text // empty')"
assert_eq  "deadbeef" "${read_text}" "expected resource contents to match"

test_pass "MCP completions/resources behave as expected"
