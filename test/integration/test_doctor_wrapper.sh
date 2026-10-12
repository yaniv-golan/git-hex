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

test_run_tool_via_wrapper() {
	(
		if ! command -v mcp-bash >/dev/null 2>&1; then
			printf 'SKIP: run-tool via git-hex.sh needs mcp-bash on PATH\n'
			return 0
		fi
		local tmp_dir repo
		tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.runtool.XXXXXX")"
		trap 'rm -rf "${tmp_dir}"' EXIT
		repo="${tmp_dir}/repo"
		git init -q "${repo}"
		git -C "${repo}" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m one

		# As documented: no allowlist set, so the launcher's tool list applies.
		capture env -u MCPBASH_TOOL_ALLOWLIST bash "${PROJECT_ROOT}/git-hex.sh" run-tool git-hex-getRebasePlan \
			--roots "${repo}" --args "{\"repoPath\": \"${repo}\", \"count\": 1}"
		assert_eq "0" "${CAPTURE_STATUS}" "git-hex.sh run-tool should succeed (output: ${CAPTURE_OUTPUT})"
		assert_contains "${CAPTURE_OUTPUT}" '"structuredContent"' "git-hex.sh run-tool should print the tool result"
		test_pass "git-hex.sh run-tool runs a tool"
	)
}

test_run_tool_refuses_old_mcp_bash() {
	(
		local tmp_dir
		tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.oldmcp.XXXXXX")"
		trap 'rm -rf "${tmp_dir}"' EXIT
		mkdir -p "${tmp_dir}/bin"
		# A stub that reports an old version and fails if it is ever asked to run a tool.
		# shellcheck disable=SC2016  # $1 and $* belong to the stub script
		printf '%s\n' '#!/bin/sh' 'if [ "$1" = "--version" ]; then echo "mcp-bash 1.7.0"; exit 0; fi' 'echo "stub ran: $*"; exit 0' >"${tmp_dir}/bin/mcp-bash"
		chmod +x "${tmp_dir}/bin/mcp-bash"

		capture env PATH="${tmp_dir}/bin:${PATH}" bash "${PROJECT_ROOT}/git-hex.sh" run-tool git-hex-getRebasePlan --args '{}'
		assert_ne "0" "${CAPTURE_STATUS}" "run-tool should refuse mcp-bash older than 1.8"
		assert_contains "${CAPTURE_OUTPUT}" "1.8" "the refusal should name the required version"
		if printf '%s' "${CAPTURE_OUTPUT}" | grep -q 'stub ran'; then
			test_fail "run-tool should not run the old mcp-bash"
		fi
		test_pass "git-hex.sh run-tool refuses mcp-bash older than 1.8"
	)
}

echo "=== Testing git-hex.sh vendored runtime behavior ==="
test_vendored_runtime_present
test_install_prints_guidance
test_missing_vendored_runtime_error
test_run_tool_via_wrapper
test_run_tool_refuses_old_mcp_bash

echo ""
echo "All vendored runtime tests passed!"
