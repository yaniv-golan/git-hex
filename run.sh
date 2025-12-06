#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="${MCPBASH_HOME:-$HOME/mcp-bash-framework}"

# Framework version pinning for reproducible installs
# Update this when upgrading to a new framework version
FRAMEWORK_VERSION="${MCPBASH_VERSION:-v0.4.0}"

# Auto-install framework if missing
if [ ! -f "${FRAMEWORK_DIR}/bin/mcp-bash" ]; then
	echo "Installing mcp-bash framework ${FRAMEWORK_VERSION}..." >&2
	git clone --depth 1 --branch "${FRAMEWORK_VERSION}" \
		https://github.com/yaniv-golan/mcp-bash-framework.git "${FRAMEWORK_DIR}"
fi

export MCPBASH_PROJECT_ROOT="${SCRIPT_DIR}"
exec "${FRAMEWORK_DIR}/bin/mcp-bash" "$@"

