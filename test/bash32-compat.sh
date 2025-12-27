#!/usr/bin/env bash
# Bash 3.2 compatibility test runner
#
# This script runs tests explicitly with bash 3.2 to catch compatibility issues
# that might only manifest on macOS CI (which uses bash 3.2.57).
#
# Usage:
#   ./test/bash32-compat.sh              # Run all integration tests with bash 3.2
#   ./test/bash32-compat.sh test_foo.sh  # Run specific test with bash 3.2
#
# Common bash 3.2 issues:
#   - "${empty_array[@]}" with set -u causes silent exit (unbound variable)
#   - Some process substitution edge cases behave differently

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find bash 3.2
BASH32=""
if [[ "$(uname)" == "Darwin" ]]; then
	# macOS ships with bash 3.2 at /bin/bash
	if /bin/bash --version 2>/dev/null | head -1 | grep -q 'version 3\.2'; then
		BASH32="/bin/bash"
	fi
fi

if [ -z "${BASH32}" ]; then
	printf 'ERROR: bash 3.2 not found.\n' >&2
	printf 'This test is designed for macOS where /bin/bash is bash 3.2.\n' >&2
	printf 'On Linux/Windows, use CI to test bash 3.2 compatibility.\n' >&2
	exit 1
fi

printf 'Using bash 3.2: %s\n' "${BASH32}"
"${BASH32}" --version | head -1
printf '\n'

# Run the specified test or all integration tests
if [ $# -gt 0 ]; then
	# Run specific test
	test_script="$1"
	if [ ! -f "${test_script}" ]; then
		test_script="${SCRIPT_DIR}/integration/${test_script}"
	fi
	if [ ! -f "${test_script}" ]; then
		printf 'ERROR: Test script not found: %s\n' "$1" >&2
		exit 1
	fi
	printf '=== Running %s with bash 3.2 ===\n' "${test_script}"
	"${BASH32}" "${test_script}"
else
	# Run all integration tests
	printf '=== Running integration tests with bash 3.2 ===\n\n'
	export SHELL="${BASH32}"
	# Use bash 3.2 to run the integration test runner
	"${BASH32}" "${SCRIPT_DIR}/integration/run.sh"
fi

printf '\n✅ Bash 3.2 compatibility test passed!\n'
