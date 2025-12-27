#!/usr/bin/env bash
# Lint layer: run shellcheck and shfmt with Bash 3.2 settings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/env.sh disable=SC1091
. "${SCRIPT_DIR}/common/env.sh"
# shellcheck source=common/assert.sh disable=SC1091
. "${SCRIPT_DIR}/common/assert.sh"

test_require_command shellcheck
test_require_command shfmt
test_require_command git

cd "${PROJECT_ROOT}"

existing_files=()
while IFS= read -r -d '' path; do
	case "${path}" in
	*.orig) continue ;;
	esac
	if [ -f "${path}" ]; then
		existing_files+=("${path}")
	fi
done < <(git ls-files -z -- '*.sh')

if [ ${#existing_files[@]} -eq 0 ]; then
	printf 'No tracked shell scripts found.\n'
	exit 0
fi

printf 'Running shellcheck...\n'
if ! shellcheck -x "${existing_files[@]}"; then
	test_fail "shellcheck detected issues"
fi

printf 'Running shfmt...\n'
SHFMT_FLAGS=(-bn -kp)
if ! shfmt -d "${SHFMT_FLAGS[@]}" "${existing_files[@]}"; then
	test_fail "shfmt formatting drift detected"
fi

# Bash 3.2 compatibility: Check for potentially unsafe empty array expansions.
# In bash 3.2 with set -u, "${arr[@]}" on an empty array causes silent exit.
# Safe patterns:
#   - [ "${#arr[@]}" -gt 0 ] && use "${arr[@]}"
#   - ${arr[@]+"${arr[@]}"} (expands to nothing if unset/empty)
#   - Prior guard: if [ ${#arr[@]} -eq 0 ]; then exit/return/fail; fi
printf 'Checking for bash 3.2 empty array safety...\n'
unsafe_patterns=()
# Pattern to find "${identifier[@]}" - grep extended regex
# shellcheck disable=SC2016
array_pattern='"\$\{[a-zA-Z_][a-zA-Z0-9_]*\[@\]\}"'

# Check if array has a prior guard (length check before the usage line)
# If someone checks ${#arrname[@]} before using the array, they're aware of the issue
# shellcheck disable=SC2016
has_prior_guard() {
	local file="$1" arrname="$2" use_line="$3"
	# Look for ${#arrname[@]} check before the usage line
	# This includes: [ ${#arr[@]} -eq 0 ], [ ${#arr[@]} -gt 0 ], etc.
	head -n "$((use_line - 1))" "${file}" 2>/dev/null \
		| grep -q "\${#${arrname}\[@\]}" 2>/dev/null
}

for file in "${existing_files[@]}"; do
	# Skip files that don't use set -u (they don't have this problem)
	if ! grep -q 'set -[^#]*u' "${file}" 2>/dev/null; then
		continue
	fi

	# Find lines with "${arr[@]}" that aren't guarded
	grep_output="$(grep -n -E "${array_pattern}" "${file}" 2>/dev/null || true)"
	[ -z "${grep_output}" ] && continue

	while IFS=: read -r lineno line; do
		[ -z "${lineno}" ] && continue
		# Skip lines marked as verified safe (requires explanation: # bash32-safe: reason)
		case "${line}" in *'# bash32-safe:'*) continue ;; esac
		# Skip comments where the array pattern is in the comment
		# shellcheck disable=SC2016
		case "${line}" in *'#'*'${'*'[@]}'*) continue ;; esac

		# Skip safe patterns:
		# - ${arr[@]+"${arr[@]}"} - conditional expansion
		# - Lines with multiple array expansions (likely comparing/iterating)
		# - Lines checking $# (argument count)
		# - Length check on same line
		# shellcheck disable=SC2016
		case "${line}" in
		*'[@]+"${'*) continue ;;
		*'[@]}"'*'[@]}'*) continue ;;
		*'$#'*) continue ;;
		*'${#'*'[@]}'*'-gt 0'*) continue ;;
		*'${#'*'[@]}'*'-ne 0'*) continue ;;
		esac

		# Extract array name from the line (first match)
		# shellcheck disable=SC2016
		arrname="$(printf '%s' "${line}" | sed -n 's/.*"\${\([a-zA-Z_][a-zA-Z0-9_]*\)\[@\]}".*/\1/p' | head -1)"
		[ -z "${arrname}" ] && continue

		# Check if there's a prior guard for this array
		if has_prior_guard "${file}" "${arrname}" "${lineno}"; then
			continue
		fi

		# Flag potential issues - manual review needed
		unsafe_patterns+=("${file}:${lineno}: ${line}")
	done <<<"${grep_output}"
done

if [ ${#unsafe_patterns[@]} -gt 0 ]; then
	printf '\n⚠️  Potential bash 3.2 empty array issues (manual review needed):\n'
	# shellcheck disable=SC2016
	printf '   In bash 3.2 with set -u, "${arr[@]}" on empty array causes silent exit.\n\n'
	printf '   Fixes:\n'
	# shellcheck disable=SC2016
	printf '   1. ${arr[@]+"${arr[@]}"}           - expands to nothing if empty (recommended)\n'
	# shellcheck disable=SC2016
	printf '   2. [ "${#arr[@]}" -gt 0 ] &&       - guard with length check first\n'
	printf '   3. # bash32-safe: <reason>         - suppress with mandatory explanation\n\n'
	printf '   See: https://github.com/koalaman/shellcheck/issues/250\n\n'
	for pattern in "${unsafe_patterns[@]}"; do
		printf '   %s\n' "${pattern}"
	done
	printf '\n'
	# Note: This is a warning, not a failure - too many false positives
	# test_fail "Potential bash 3.2 array safety issues found"
fi

printf 'Lint completed successfully.\n'
