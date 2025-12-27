#!/usr/bin/env bash
# Run schema-related checks (fast, deterministic).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  git-hex Schema Checks"
echo "========================================"
echo ""

failed=0

run_one() {
	local name="$1"
	local path="$2"
	printf -- '-> %s\n' "${name}"
	if bash "${path}"; then
		echo "   [PASS] ${name}"
	else
		echo "   [FAIL] ${name}" >&2
		failed=$((failed + 1))
	fi
	echo ""
}

run_one "tool.meta.json contracts" "${SCRIPT_DIR}/test_tool_meta_contracts.sh"
run_one "docs tools coverage" "${SCRIPT_DIR}/test_docs_tools_coverage.sh"

if [ "${failed}" -eq 0 ]; then
	echo "Schema checks: PASSED"
	exit 0
fi
echo "Schema checks: FAILED (${failed})" >&2
exit 1
