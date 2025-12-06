#!/usr/bin/env bash
# Run all integration tests for git-hex
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  git-hex Integration Tests"
echo "========================================"
echo ""

failed=0
passed=0

for test_file in "${SCRIPT_DIR}"/test_*.sh; do
	if [ -f "${test_file}" ]; then
		test_name="$(basename "${test_file}")"
		echo "Running ${test_name}..."
		echo "----------------------------------------"
		if bash "${test_file}"; then
			passed=$((passed + 1))
		else
			failed=$((failed + 1))
			echo "FAILED: ${test_name}"
		fi
		echo ""
	fi
done

echo "========================================"
echo "  Results: ${passed} passed, ${failed} failed"
echo "========================================"

if [ "${failed}" -gt 0 ]; then
	exit 1
fi

