#!/usr/bin/env bash
# Test assertion helpers for git-hex

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_fail() {
	local message="$1"
	printf "${RED}FAIL${NC}: %s\n" "${message}" >&2
	exit 1
}

test_pass() {
	local message="$1"
	printf "${GREEN}PASS${NC}: %s\n" "${message}"
}

assert_eq() {
	local expected="$1"
	local actual="$2"
	local message="${3:-Values should be equal}"
	
	if [ "${expected}" != "${actual}" ]; then
		test_fail "${message} (expected: '${expected}', got: '${actual}')"
	fi
}

assert_ne() {
	local unexpected="$1"
	local actual="$2"
	local message="${3:-Values should not be equal}"
	
	if [ "${unexpected}" = "${actual}" ]; then
		test_fail "${message} (got unexpected value: '${actual}')"
	fi
}

assert_contains() {
	local haystack="$1"
	local needle="$2"
	local message="${3:-String should contain substring}"
	
	if [[ "${haystack}" != *"${needle}"* ]]; then
		test_fail "${message} (looking for '${needle}' in '${haystack}')"
	fi
}

assert_file_exists() {
	local path="$1"
	local message="${2:-File should exist}"
	
	if [ ! -f "${path}" ]; then
		test_fail "${message}: ${path}"
	fi
}

assert_dir_exists() {
	local path="$1"
	local message="${2:-Directory should exist}"
	
	if [ ! -d "${path}" ]; then
		test_fail "${message}: ${path}"
	fi
}

assert_json_field() {
	local json="$1"
	local field="$2"
	local expected="$3"
	local message="${4:-JSON field should match}"
	
	local actual
	actual="$(printf '%s' "${json}" | jq -r "${field}" 2>/dev/null || echo "")"
	
	if [ "${expected}" != "${actual}" ]; then
		test_fail "${message} (field ${field}: expected '${expected}', got '${actual}')"
	fi
}

