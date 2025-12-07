#!/usr/bin/env bash
# Orchestrate integration tests with per-test logs and TAP-style status output.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERBOSE="${VERBOSE:-0}"
UNICODE="${UNICODE:-0}"
KEEP_INTEGRATION_LOGS="${KEEP_INTEGRATION_LOGS:-0}"

SUITE_TMP="${GITHEX_INTEGRATION_TMP:-$(mktemp -d "${TMPDIR:-/tmp}/githex.integration.XXXXXX")}"
LOG_DIR="${SUITE_TMP}/logs"
mkdir -p "${LOG_DIR}"

SUITE_FAILED=0
cleanup_suite_tmp() {
	# Preserve logs on failure or when explicitly requested
	if [ "${KEEP_INTEGRATION_LOGS}" = "1" ] || [ "${SUITE_FAILED}" -ne 0 ]; then
		return
	fi
	if [ -n "${SUITE_TMP}" ] && [ -d "${SUITE_TMP}" ]; then
		rm -rf "${SUITE_TMP}" 2>/dev/null || true
	fi
}
trap cleanup_suite_tmp EXIT INT TERM

PASS_ICON="[PASS]"
FAIL_ICON="[FAIL]"
if [ "${UNICODE}" = "1" ]; then
	PASS_ICON="✅"
	FAIL_ICON="❌"
fi

TESTS=()
while IFS= read -r path; do
	[ -f "${path}" ] || continue
	TESTS+=("$(basename "${path}")")
done < <(find "${SCRIPT_DIR}" -maxdepth 1 -type f -name 'test_*.sh' | sort)

if [ "${#TESTS[@]}" -eq 0 ]; then
	printf 'No integration tests discovered under %s\n' "${SCRIPT_DIR}" >&2
	exit 1
fi

passed=0
failed=0
total="${#TESTS[@]}"

run_test() {
	local test_script="$1"
	local index="$2"
	local log_file start end elapsed status

	log_file="${LOG_DIR}/${test_script}.log"
	start="$(date +%s)"

	if [ "${VERBOSE}" = "1" ]; then
		(
			set -o pipefail
			bash "${SCRIPT_DIR}/${test_script}" 2>&1 | while IFS= read -r line || [ -n "${line}" ]; do
				printf '[%s] %s\n' "${test_script}" "${line}"
			done
			exit "${PIPESTATUS[0]}"
		) | tee "${log_file}"
		status="${PIPESTATUS[0]}"
	else
		if bash "${SCRIPT_DIR}/${test_script}" >"${log_file}" 2>&1; then
			status=0
		else
			status=$?
		fi
	fi

	end="$(date +%s)"
	elapsed=$((end - start))

	if [ "${status}" -eq 0 ]; then
		printf '[%02d/%02d] %s ... %s (%ss)\n' "${index}" "${total}" "${test_script}" "${PASS_ICON}" "${elapsed}"
		passed=$((passed + 1))
	else
		printf '[%02d/%02d] %s ... %s (%ss)\n' "${index}" "${total}" "${test_script}" "${FAIL_ICON}" "${elapsed}" >&2
		printf '  log: %s\n' "${log_file}" >&2
		if [ "${VERBOSE}" != "1" ]; then
			printf '  --- log start ---\n' >&2
			cat "${log_file}" >&2 || true
			printf '  --- log end ---\n' >&2
		fi
		failed=$((failed + 1))
	fi
}

index=1
suite_start="$(date +%s)"

for test_script in "${TESTS[@]}"; do
	run_test "${test_script}" "${index}"
	index=$((index + 1))
done

suite_end="$(date +%s)"
suite_elapsed=$((suite_end - suite_start))

log_note="${LOG_DIR}"
if [ "${KEEP_INTEGRATION_LOGS}" != "1" ] && [ "${failed}" -eq 0 ]; then
	log_note="${LOG_DIR} (will be removed on success; preserved on failure)"
fi

printf '\nIntegration summary: %d passed, %d failed (logs: %s, elapsed: %ss)\n' \
	"${passed}" "${failed}" "${log_note}" "${suite_elapsed}"

if [ "${failed}" -ne 0 ]; then
	SUITE_FAILED=1
	exit 1
fi
