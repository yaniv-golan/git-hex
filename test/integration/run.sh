#!/usr/bin/env bash
# Orchestrate integration tests with per-test logs and TAP-style status output.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERBOSE="${VERBOSE:-0}"
UNICODE="${UNICODE:-0}"
KEEP_INTEGRATION_LOGS="${KEEP_INTEGRATION_LOGS:-0}"

# Optional filtering
GITHEX_TEST_PROFILE="${GITHEX_TEST_PROFILE:-}"
GITHEX_TEST_INCLUDE="${GITHEX_TEST_INCLUDE:-}"
GITHEX_TEST_EXCLUDE="${GITHEX_TEST_EXCLUDE:-}"
GITHEX_TEST_STRICT="${GITHEX_TEST_STRICT:-0}"

# Detect CI environment
IS_CI="${CI:-${GITHUB_ACTIONS:-0}}"

SUITE_TMP="${GITHEX_INTEGRATION_TMP:-$(mktemp -d "${TMPDIR:-/tmp}/githex.integration.XXXXXX")}"
LOG_DIR="${SUITE_TMP}/logs"
SUMMARY_FILE="${SUITE_TMP}/failure-summary.txt"
ENV_SNAPSHOT="${SUITE_TMP}/environment.txt"
mkdir -p "${LOG_DIR}"

# Capture environment snapshot for debugging
capture_environment() {
	{
		printf '=== Environment Snapshot ===\n'
		printf 'Timestamp: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
		printf 'OS: %s\n' "$(uname -a)"
		printf 'Bash: %s\n' "${BASH_VERSION}"
		printf 'Shell options: %s\n' "$-"
		printf 'PWD: %s\n' "${PWD}"
		printf '\n--- Relevant Environment Variables ---\n'
		env | grep -E '^(GIT_|MCPBASH_|GITHEX_|PATH=|HOME=|TMPDIR=|RUNNER_|GITHUB_)' | sort || true
		printf '\n--- Tool Versions ---\n'
		printf 'git: %s\n' "$(git --version 2>/dev/null || echo 'not found')"
		printf 'jq: %s\n' "$(jq --version 2>/dev/null || echo 'not found')"
		printf 'mcp-bash: %s\n' "$(mcp-bash --version 2>/dev/null || echo 'not found')"
	} >"${ENV_SNAPSHOT}" 2>&1
}
capture_environment

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

WINDOWS_SMOKE_TESTS=(
	test_existing_tools.sh
	test_get_rebase_plan.sh
	test_doctor_wrapper.sh
	test_read_only_mode.sh
	test_rebase_with_plan.sh
)

TESTS=()
while IFS= read -r path; do
	[ -f "${path}" ] || continue
	TESTS+=("$(basename "${path}")")
done < <(find "${SCRIPT_DIR}" -maxdepth 1 -type f -name 'test_*.sh' | sort)

if [ "${#TESTS[@]}" -eq 0 ]; then
	printf 'No integration tests discovered under %s\n' "${SCRIPT_DIR}" >&2
	exit 1
fi

split_list() {
	# Split on commas and whitespace.
	# shellcheck disable=SC2206 # intended word splitting
	local items=(${1//,/ })
	printf '%s\n' "${items[@]}"
}

filter_tests() {
	local -a resolved
	resolved=("${TESTS[@]}")

	if [ -n "${GITHEX_TEST_PROFILE}" ]; then
		case "${GITHEX_TEST_PROFILE}" in
		windows-smoke)
			resolved=("${WINDOWS_SMOKE_TESTS[@]}")
			;;
		*)
			printf 'Unknown GITHEX_TEST_PROFILE: %s\n' "${GITHEX_TEST_PROFILE}" >&2
			exit 2
			;;
		esac
	fi

	if [ -n "${GITHEX_TEST_INCLUDE}" ]; then
		local -a include
		include=()
		while IFS= read -r t; do
			include+=("${t}")
		done < <(split_list "${GITHEX_TEST_INCLUDE}")
		resolved=()
		local t
		for t in "${include[@]}"; do
			[ -n "${t}" ] || continue
			resolved+=("${t}")
		done
	fi

	if [ -n "${GITHEX_TEST_EXCLUDE}" ]; then
		local -a exclude filtered
		exclude=()
		while IFS= read -r t; do
			exclude+=("${t}")
		done < <(split_list "${GITHEX_TEST_EXCLUDE}")
		filtered=()
		local t ex matched
		for t in "${resolved[@]}"; do
			matched=0
			for ex in "${exclude[@]}"; do
				[ -n "${ex}" ] || continue
				if [ "${t}" = "${ex}" ]; then
					matched=1
					break
				fi
			done
			if [ "${matched}" -eq 0 ]; then
				filtered+=("${t}")
			fi
		done
		resolved=("${filtered[@]}")
	fi

	# Validate selected tests exist in discovered list.
	local -a missing
	missing=()
	local t found d
	for t in "${resolved[@]}"; do
		found=0
		for d in "${TESTS[@]}"; do
			if [ "${t}" = "${d}" ]; then
				found=1
				break
			fi
		done
		if [ "${found}" -eq 0 ]; then
			missing+=("${t}")
		fi
	done

	if [ "${#missing[@]}" -gt 0 ]; then
		printf 'Selected tests not found under %s:\n' "${SCRIPT_DIR}" >&2
		printf '  - %s\n' "${missing[@]}" >&2
		if [ "${GITHEX_TEST_STRICT}" = "1" ]; then
			exit 2
		fi
		# Non-strict: drop missing tests.
		local -a existing
		existing=()
		for t in "${resolved[@]}"; do
			found=0
			for d in "${TESTS[@]}"; do
				if [ "${t}" = "${d}" ]; then
					found=1
					break
				fi
			done
			if [ "${found}" -eq 1 ]; then
				existing+=("${t}")
			fi
		done
		resolved=("${existing[@]}")
	fi

	TESTS=("${resolved[@]}")
}

if [ -n "${GITHEX_TEST_PROFILE}" ] || [ -n "${GITHEX_TEST_INCLUDE}" ] || [ -n "${GITHEX_TEST_EXCLUDE}" ]; then
	filter_tests
fi

printf 'Discovered %d integration tests; running %d\n' "$(printf '%s\n' "${TESTS[@]}" | wc -l | tr -d ' ')" "${#TESTS[@]}"
if [ "${#TESTS[@]}" -gt 0 ]; then
	printf 'Selected tests:\n'
	printf '  - %s\n' "${TESTS[@]}"
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

	printf '[%02d/%02d] %s ... RUNNING (log: %s)\n' "${index}" "${total}" "${test_script}" "${log_file}"

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

		# Append to failure summary
		{
			printf '\n=== FAILED: %s ===\n' "${test_script}"
			printf 'Exit code: %d\n' "${status}"
			printf 'Duration: %ss\n' "${elapsed}"
			printf 'Log file: %s\n' "${log_file}"
			printf 'Timestamp: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
			# Extract key error lines (last error, tool failures)
			if [ -f "${log_file}" ]; then
				printf '\n--- Key Error Lines ---\n'
				grep -E '(FAIL|ERROR|error:|_mcpToolError|unbound variable|command not found)' "${log_file}" | tail -20 || true
			fi
			printf '\n'
		} >>"${SUMMARY_FILE}"

		# Emit GitHub Actions annotation if in CI
		if [ "${IS_CI}" != "0" ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
			# Extract first error message for annotation
			local error_msg
			error_msg="$(grep -E '(FAIL|ERROR|error:)' "${log_file}" 2>/dev/null | head -1 || echo "Test failed")"
			# Escape special characters for GitHub annotation
			error_msg="${error_msg//'%'/'%25'}"
			error_msg="${error_msg//$'\n'/'%0A'}"
			error_msg="${error_msg//$'\r'/'%0D'}"
			printf '::error file=test/integration/%s,title=Test Failed::%s\n' "${test_script}" "${error_msg}"
		fi
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

	# Print failure summary and environment info
	if [ -f "${SUMMARY_FILE}" ]; then
		printf '\n=== Failure Summary ===\n' >&2
		cat "${SUMMARY_FILE}" >&2
	fi

	printf '\n=== Environment (see %s for full details) ===\n' "${ENV_SNAPSHOT}" >&2
	head -15 "${ENV_SNAPSHOT}" >&2 || true

	# GitHub Actions job summary
	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		{
			printf '## Integration Test Results\n\n'
			printf '**%d passed, %d failed** (elapsed: %ss)\n\n' "${passed}" "${failed}" "${suite_elapsed}"
			printf '### Failed Tests\n\n'
			if [ -f "${SUMMARY_FILE}" ]; then
				printf '```\n'
				cat "${SUMMARY_FILE}"
				printf '```\n'
			fi
			printf '\n### Environment\n\n'
			printf '```\n'
			cat "${ENV_SNAPSHOT}"
			printf '```\n'
		} >>"${GITHUB_STEP_SUMMARY}"
	fi

	exit 1
fi
