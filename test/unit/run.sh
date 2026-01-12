#!/usr/bin/env bash
# Run all unit tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Running git-hex unit tests"
echo "=========================================="
echo ""

failed=0
for test_file in "${SCRIPT_DIR}"/test_*.sh; do
	[ -f "${test_file}" ] || continue
	echo "--- Running $(basename "${test_file}") ---"
	if ! bash "${test_file}"; then
		failed=1
		echo "FAILED: $(basename "${test_file}")"
	fi
	echo ""
done

if [ "${failed}" -eq 1 ]; then
	echo "Some unit tests failed!"
	exit 1
fi

echo "=========================================="
echo "All unit tests passed!"
echo "=========================================="
