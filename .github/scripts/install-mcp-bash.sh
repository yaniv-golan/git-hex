#!/usr/bin/env bash
# Install the mcp-bash CLI for CI, pinned to the release and checksum the
# Dockerfile sets (the one place the framework version is pinned), and only
# when that matches the vendored runtime in .mcp-bash/VERSION.
# Extra arguments go to install.sh (e.g. --dir).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

dockerfile_arg() {
	sed -n "s/^ARG $1=//p" "${root}/Dockerfile" | tr -d '\r[:space:]'
}

version="$(dockerfile_arg FRAMEWORK_VERSION)"
sha="$(dockerfile_arg FRAMEWORK_SHA256)"
vendored="$(tr -d '\r[:space:]' <"${root}/.mcp-bash/VERSION")"

if [ -z "${version}" ] || [ -z "${sha}" ]; then
	echo "error: FRAMEWORK_VERSION or FRAMEWORK_SHA256 is missing from the Dockerfile" >&2
	exit 1
fi
if [ "${version#v}" != "${vendored}" ]; then
	echo "error: the Dockerfile pins mcp-bash ${version}, but the vendored runtime is ${vendored}" >&2
	exit 1
fi

# GitHub sometimes answers a download with a 5xx; try a few times.
attempt=1
until curl -fsSL "https://raw.githubusercontent.com/yaniv-golan/mcp-bash-framework/${version}/install.sh" \
	| bash -s -- --yes --version "${version}" --verify "${sha}" "$@"; do
	if [ "${attempt}" -ge 3 ]; then
		echo "error: installing mcp-bash ${version} failed ${attempt} times" >&2
		exit 1
	fi
	echo "Install failed (attempt ${attempt}); retrying in $((attempt * 10))s..." >&2
	sleep $((attempt * 10))
	attempt=$((attempt + 1))
done
