#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/assert.sh"

CAPTURE_STATUS=0
CAPTURE_OUTPUT=""

capture() {
	local output rc
	set +e
	output="$("$@" 2>&1)"
	rc=$?
	set -e
	CAPTURE_STATUS="${rc}"
	CAPTURE_OUTPUT="${output}"
}

test_vendored_runtime_present() {
	(
		local runtime="${PROJECT_ROOT}/.mcp-bash/bin/mcp-bash"
		assert_file_exists "${runtime}" "vendored mcp-bash binary should exist"
		if [ ! -x "${runtime}" ]; then
			test_fail "vendored mcp-bash binary should be executable"
		fi
		assert_file_exists "${PROJECT_ROOT}/.mcp-bash/vendor.json" "vendor.json should exist"
		test_pass "vendored runtime is present and executable"
	)
}

test_install_prints_guidance() {
	(
		capture bash "${PROJECT_ROOT}/git-hex.sh" install
		assert_eq "0" "${CAPTURE_STATUS}" "install should exit 0"
		assert_contains "${CAPTURE_OUTPUT}" "no longer needed" "install should say no longer needed"
		assert_contains "${CAPTURE_OUTPUT}" "mcp-bash" "install should mention mcp-bash vendor workflow"
		test_pass "install prints guidance and exits 0"
	)
}

test_missing_vendored_runtime_error() {
	(
		local tmp_dir
		tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.vendor.XXXXXX")"
		trap 'rm -rf "${tmp_dir}"' EXIT

		cp "${PROJECT_ROOT}/git-hex.sh" "${tmp_dir}/"
		cp "${PROJECT_ROOT}/VERSION" "${tmp_dir}/"

		capture bash "${tmp_dir}/git-hex.sh"
		assert_ne "0" "${CAPTURE_STATUS}" "should exit non-zero when vendored runtime is missing"
		assert_contains "${CAPTURE_OUTPUT}" "Vendored mcp-bash runtime not found" "should report missing vendored runtime"
		test_pass "missing vendored runtime produces expected error"
	)
}

echo "=== Testing git-hex.sh vendored runtime behavior ==="
test_vendored_runtime_present
test_install_prints_guidance
test_missing_vendored_runtime_error

echo ""
echo "All vendored runtime tests passed!"
