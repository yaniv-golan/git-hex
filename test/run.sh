#!/usr/bin/env bash
# Run all tests for git-hex
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  git-hex Test Suite"
echo "========================================"
echo ""

total_failed=0

# Run integration tests
if [ -d "${SCRIPT_DIR}/integration" ]; then
	echo ">>> Running Integration Tests <<<"
	if bash "${SCRIPT_DIR}/integration/run.sh"; then
		echo "Integration tests: PASSED"
	else
		echo "Integration tests: FAILED"
		total_failed=$((total_failed + 1))
	fi
	echo ""
fi

# Run security tests
if [ -d "${SCRIPT_DIR}/security" ]; then
	echo ">>> Running Security Tests <<<"
	if bash "${SCRIPT_DIR}/security/run.sh"; then
		echo "Security tests: PASSED"
	else
		echo "Security tests: FAILED"
		total_failed=$((total_failed + 1))
	fi
	echo ""
fi

echo "========================================"
if [ "${total_failed}" -eq 0 ]; then
	echo "  All test suites PASSED"
	echo "========================================"
	exit 0
else
	echo "  ${total_failed} test suite(s) FAILED"
	echo "========================================"
	exit 1
fi
