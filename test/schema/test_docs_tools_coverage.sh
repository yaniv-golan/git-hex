#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCS_FILE="${ROOT_DIR}/docs/reference/tools.md"

if ! command -v jq >/dev/null 2>&1; then
	echo "ERROR: jq is required for schema checks" >&2
	exit 2
fi

if [ ! -f "${DOCS_FILE}" ]; then
	echo "ERROR: missing docs file: ${DOCS_FILE}" >&2
	exit 2
fi

failures=0
fail() {
	echo "ERROR: $*" >&2
	failures=$((failures + 1))
}

while IFS= read -r meta; do
	[ -n "${meta}" ] || continue
	tool_name="$(jq -r '.name // empty' "${meta}" 2>/dev/null || echo "")"
	[ -n "${tool_name}" ] || continue
	if ! grep -Fq "### ${tool_name}" "${DOCS_FILE}" 2>/dev/null; then
		fail "docs/reference/tools.md is missing section header: ### ${tool_name}"
	fi
done < <(find "${ROOT_DIR}/tools" -mindepth 2 -maxdepth 2 -name 'tool.meta.json' | sort)

if [ "${failures}" -ne 0 ]; then
	exit 1
fi
