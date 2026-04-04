#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ==============================================================================
# Vendored Runtime
# ==============================================================================
# The mcp-bash runtime is vendored in .mcp-bash/ (committed to the repo).
# To upgrade: mcp-bash vendor --upgrade && mcp-bash vendor --verify
# See .mcp-bash/vendor.json for version and integrity info.

FRAMEWORK_DIR="${SCRIPT_DIR}/.mcp-bash"

if [ ! -x "${FRAMEWORK_DIR}/bin/mcp-bash" ]; then
	echo "ERROR: Vendored mcp-bash runtime not found at ${FRAMEWORK_DIR}" >&2
	echo "" >&2
	echo "This should not happen if you cloned the repository correctly." >&2
	echo "Try: git checkout -- .mcp-bash/" >&2
	exit 1
fi

# ==============================================================================
# Debug Mode
# ==============================================================================
# Enable debug mode via:
#   1. GIT_HEX_DEBUG=1 environment variable
#   2. server.d/.debug file (mcp-bash 0.9.5+ native detection)
#
# Quick enable:  touch server.d/.debug
# Quick disable: rm server.d/.debug

if [[ "${GIT_HEX_DEBUG:-}" == "1" ]]; then
	export MCPBASH_LOG_LEVEL="${MCPBASH_LOG_LEVEL:-debug}"
fi

# Cache version at startup (for debug banner)
GIT_HEX_VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "unknown")

# ==============================================================================
# Subcommand Handling
# ==============================================================================

# Handle legacy 'install' subcommand
if [ "${1:-}" = "install" ]; then
	echo "The 'install' subcommand is no longer needed." >&2
	echo "The mcp-bash runtime is vendored in the repository." >&2
	echo "" >&2
	echo "To upgrade the vendored runtime:" >&2
	echo "  mcp-bash vendor --upgrade" >&2
	echo "  mcp-bash vendor --verify" >&2
	echo "  git add .mcp-bash/" >&2
	echo "  git commit -m 'upgrade vendored mcp-bash runtime'" >&2
	exit 0
fi

export MCPBASH_PROJECT_ROOT="${SCRIPT_DIR}"

# Handle developer CLI subcommands (validate, doctor) — these require the full
# mcp-bash CLI (not included in the vendored runtime). Use system-installed mcp-bash.
if [ "${1:-}" = "validate" ] || [ "${1:-}" = "doctor" ]; then
	if command -v mcp-bash >/dev/null 2>&1; then
		exec mcp-bash "$@"
	else
		echo "The '${1}' subcommand requires mcp-bash installed on your system." >&2
		echo "Install via: brew install yaniv-golan/mcp-bash/mcp-bash" >&2
		exit 1
	fi
fi

# ==============================================================================
# Tool Allowlist
# ==============================================================================
# mcp-bash-framework v0.7.0+: tool execution is deny-by-default unless allowlisted.
if [ -z "${MCPBASH_TOOL_ALLOWLIST:-}" ]; then
	GIT_HEX_TOOL_ALLOWLIST_READONLY="git-hex-getRebasePlan git-hex-checkRebaseConflicts git-hex-getConflictStatus"
	GIT_HEX_TOOL_ALLOWLIST_ALL="git-hex-getRebasePlan git-hex-checkRebaseConflicts git-hex-getConflictStatus git-hex-rebaseWithPlan git-hex-splitCommit git-hex-createFixup git-hex-amendLastCommit git-hex-cherryPickSingle git-hex-resolveConflict git-hex-continueOperation git-hex-abortOperation git-hex-undoLast"
	if [ "${GIT_HEX_READ_ONLY:-}" = "1" ]; then
		export MCPBASH_TOOL_ALLOWLIST="${GIT_HEX_TOOL_ALLOWLIST_READONLY}"
	else
		export MCPBASH_TOOL_ALLOWLIST="${GIT_HEX_TOOL_ALLOWLIST_ALL}"
	fi
fi

# Print debug banner if debug mode enabled
if [[ "${GIT_HEX_DEBUG:-}" == "1" ]]; then
	VENDOR_VERSION=$(cat "${FRAMEWORK_DIR}/VERSION" 2>/dev/null || echo "unknown")
	echo "[git-hex:${GIT_HEX_VERSION}] Debug mode enabled" >&2
	echo "[git-hex:${GIT_HEX_VERSION}] Versions: git-hex=${GIT_HEX_VERSION} mcp-bash=v${VENDOR_VERSION}" >&2
	echo "[git-hex:${GIT_HEX_VERSION}] Process: pid=$$ started=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)" >&2
fi

exec "${FRAMEWORK_DIR}/bin/mcp-bash" "$@"
