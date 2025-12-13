#!/usr/bin/env bash
set -euo pipefail

# Login-aware launcher for GUI clients (e.g., macOS Claude Desktop) where PATH
# and version managers are only set in your shell profile.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_PROFILE=""

if [ -f "${HOME}/.zshrc" ]; then
	SHELL_PROFILE="${HOME}/.zshrc"
elif [ -f "${HOME}/.bash_profile" ]; then
	SHELL_PROFILE="${HOME}/.bash_profile"
elif [ -f "${HOME}/.bashrc" ]; then
	SHELL_PROFILE="${HOME}/.bashrc"
fi

if [ -n "${SHELL_PROFILE}" ]; then
	# shellcheck source=/dev/null
	. "${SHELL_PROFILE}"
fi

# Prefer PATH (after profile), then XDG location, then MCPBASH_HOME override
MCP_BASH=""
if command -v mcp-bash >/dev/null 2>&1; then
	MCP_BASH="$(command -v mcp-bash)"
elif [ -f "${HOME}/.local/bin/mcp-bash" ]; then
	MCP_BASH="${HOME}/.local/bin/mcp-bash"
elif [ -f "${MCPBASH_HOME:-}/bin/mcp-bash" ]; then
	MCP_BASH="${MCPBASH_HOME}/bin/mcp-bash"
fi

if [ -z "${MCP_BASH}" ]; then
	printf 'Error: mcp-bash not found in PATH or ~/.local/bin\n' >&2
	printf "Install (recommended, verified): curl -fsSL https://raw.githubusercontent.com/yaniv-golan/mcp-bash-framework/main/install.sh | bash -s -- --version v0.7.0 --verify \"\$MCPBASH_SHA256\"\n" >&2
	printf 'Install (fallback): curl -fsSL https://raw.githubusercontent.com/yaniv-golan/mcp-bash-framework/main/install.sh | bash -s -- --version v0.7.0\n' >&2
	exit 1
fi

export MCPBASH_PROJECT_ROOT="${SCRIPT_DIR}"

# mcp-bash-framework v0.7.0+: tool execution is deny-by-default unless allowlisted.
# Default to allowing only git-hex tools; callers can override (e.g., "*" in trusted projects).
if [ -z "${MCPBASH_TOOL_ALLOWLIST:-}" ]; then
	export MCPBASH_TOOL_ALLOWLIST="git-hex-*"
fi

exec "${MCP_BASH}" "$@"
