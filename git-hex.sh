#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Framework version pinning for reproducible installs
# Update this when upgrading to a new framework version
FRAMEWORK_VERSION="${MCPBASH_VERSION:-v0.6.0}"

# Resolve framework location with preference for XDG Base Directory defaults
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DEFAULT_FRAMEWORK_DIR="${DATA_HOME}/mcp-bash"

if [ -n "${MCPBASH_HOME:-}" ]; then
	FRAMEWORK_DIR="${MCPBASH_HOME}"
elif [ -x "${DEFAULT_FRAMEWORK_DIR}/bin/mcp-bash" ]; then
	FRAMEWORK_DIR="${DEFAULT_FRAMEWORK_DIR}"
else
	FRAMEWORK_DIR="${DEFAULT_FRAMEWORK_DIR}"
fi

# Auto-install framework if missing
if [ ! -x "${FRAMEWORK_DIR}/bin/mcp-bash" ]; then
	echo "Installing mcp-bash framework ${FRAMEWORK_VERSION} into ${FRAMEWORK_DIR}..." >&2
	mkdir -p "${FRAMEWORK_DIR%/*}"
	git clone --depth 1 --branch "${FRAMEWORK_VERSION}" \
		https://github.com/yaniv-golan/mcp-bash-framework.git "${FRAMEWORK_DIR}"
	# Create a convenience symlink matching the installer behavior
	mkdir -p "$HOME/.local/bin"
	ln -snf "${FRAMEWORK_DIR}/bin/mcp-bash" "$HOME/.local/bin/mcp-bash"
fi

export MCPBASH_PROJECT_ROOT="${SCRIPT_DIR}"
exec "${FRAMEWORK_DIR}/bin/mcp-bash" "$@"
