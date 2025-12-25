#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/assert.sh"

run_in_home() {
	local home_dir="$1"
	shift

	(
		cd "${PROJECT_ROOT}"
		HOME="${home_dir}" \
			XDG_DATA_HOME="${home_dir}/.local/share" \
			MCPBASH_HOME='' \
			bash ./git-hex.sh "$@"
	)
}

CAPTURE_STATUS=0
CAPTURE_OUTPUT=""

capture_run_in_home() {
	local home_dir="$1"
	shift

	local output rc
	set +e
	output="$(run_in_home "${home_dir}" "$@" 2>&1)"
	rc=$?
	set -e
	CAPTURE_STATUS="${rc}"
	CAPTURE_OUTPUT="${output}"
}

make_stub_framework() {
	local home_dir="$1"
	local version="$2"

	local fw_dir="${home_dir}/.local/share/mcp-bash"
	mkdir -p "${fw_dir}/bin"

	cat >"${fw_dir}/bin/mcp-bash" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\${1:-}" in
--version)
  echo "mcp-bash ${version}"
  ;;
doctor)
  echo "stub doctor ok"
  ;;
*)
  echo "stub"
  ;;
esac
EOF
	chmod +x "${fw_dir}/bin/mcp-bash"
	printf '%s\n' "marker" >"${fw_dir}/MARKER.txt"
}

make_stub_framework_082() {
	local home_dir="$1"

	local fw_dir="${home_dir}/.local/share/mcp-bash"
	mkdir -p "${fw_dir}/bin"

	cat >"${fw_dir}/bin/mcp-bash" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
--version)
  echo "mcp-bash 0.8.2"
  ;;
doctor)
  shift || true
  if [ "${1:-}" = "--help" ]; then
    echo "Usage: mcp-bash doctor [--json] [--fix] [--dry-run]"
    exit 0
  fi
  if [ "${1:-}" = "--dry-run" ]; then
    echo "framework doctor dry-run"
    exit 0
  fi
  echo "framework doctor"
  exit 0
  ;;
*)
  echo "stub"
  ;;
esac
EOF
	chmod +x "${fw_dir}/bin/mcp-bash"
}

test_missing_framework_read_only_doctor() {
	(
		local home_dir
		home_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.doctor.home.XXXXXX")"
		trap 'rm -rf "${home_dir}"' EXIT

		capture_run_in_home "${home_dir}" doctor
		assert_eq "1" "${CAPTURE_STATUS}" "doctor should exit 1 when framework missing"
		assert_contains "${CAPTURE_OUTPUT}" "doctor --fix" "doctor should instruct to use --fix"

		if [ -d "${home_dir}/.local/share/mcp-bash" ]; then
			test_fail "doctor should not create framework dir in read-only mode"
		fi
		test_pass "doctor is read-only when framework missing"
	)
}

test_missing_framework_dry_run() {
	(
		local home_dir
		home_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.doctor.home.XXXXXX")"
		trap 'rm -rf "${home_dir}"' EXIT

		capture_run_in_home "${home_dir}" doctor --dry-run
		assert_eq "1" "${CAPTURE_STATUS}" "doctor --dry-run should exit 1 when framework missing"
		assert_contains "${CAPTURE_OUTPUT}" "Would install framework" "dry-run should describe install"

		if [ -d "${home_dir}/.local/share/mcp-bash" ]; then
			test_fail "doctor --dry-run should not create framework dir"
		fi
		test_pass "doctor --dry-run reports actions without changes"
	)
}

test_too_old_framework_read_only_does_not_delete() {
	(
		local home_dir
		home_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.doctor.home.XXXXXX")"
		trap 'rm -rf "${home_dir}"' EXIT

		make_stub_framework "${home_dir}" "0.6.0"

		capture_run_in_home "${home_dir}" doctor
		assert_eq "1" "${CAPTURE_STATUS}" "doctor should exit 1 when framework too old"
		assert_contains "${CAPTURE_OUTPUT}" "requires v0.8.2+" "doctor should report minimum version requirement"

		assert_file_exists "${home_dir}/.local/share/mcp-bash/MARKER.txt" "read-only doctor should not delete existing framework"
		test_pass "doctor does not delete too-old framework without --fix"
	)
}

test_doctor_fix_refuses_mcpbash_home() {
	(
		local home_dir
		home_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.doctor.home.XXXXXX")"
		trap 'rm -rf "${home_dir}"' EXIT

		local output rc
		set +e
		output="$(
			cd "${PROJECT_ROOT}"
			HOME="${home_dir}" \
				XDG_DATA_HOME="${home_dir}/.local/share" \
				MCPBASH_HOME="${home_dir}/custom/mcp-bash" \
				bash ./git-hex.sh doctor --fix 2>&1
		)"
		rc=$?
		set -e

		assert_eq "3" "${rc}" "doctor --fix should exit 3 on policy refusal when MCPBASH_HOME is set"
		assert_contains "${output}" "does not modify MCPBASH_HOME-managed installs" "doctor --fix should explain refusal"
		test_pass "doctor --fix refuses MCPBASH_HOME targets"
	)
}

test_doctor_delegates_for_082_plus() {
	(
		local home_dir
		home_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.doctor.home.XXXXXX")"
		trap 'rm -rf "${home_dir}"' EXIT

		make_stub_framework_082 "${home_dir}"

		capture_run_in_home "${home_dir}" doctor --dry-run
		assert_eq "0" "${CAPTURE_STATUS}" "doctor --dry-run should succeed when delegated to framework >=0.8.2"
		assert_contains "${CAPTURE_OUTPUT}" "framework doctor dry-run" "doctor --dry-run should be handled by framework"
		if [[ "${CAPTURE_OUTPUT}" == *"Would install framework"* ]]; then
			test_fail "wrapper dry-run output should not appear when delegating to framework >=0.8.2"
		fi
		test_pass "doctor delegates to framework for >=0.8.2"
	)
}

echo "=== Testing git-hex.sh doctor wrapper behavior ==="
test_missing_framework_read_only_doctor
test_missing_framework_dry_run
test_too_old_framework_read_only_does_not_delete
test_doctor_fix_refuses_mcpbash_home
test_doctor_delegates_for_082_plus

echo ""
echo "All doctor wrapper tests passed!"
