#!/usr/bin/env bash
set -euo pipefail

# Launcher for macOS apps (e.g., Claude Desktop) that may not inherit your Terminal
# environment (PATH/version managers). It sources your login profile files before
# starting the server so tool discovery matches your Terminal setup.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_MCPBASH_MIN_VERSION="0.8.3"
SHELL_PROFILE=""

if [ "${GIT_HEX_ENV_NO_PROFILE:-}" != "1" ]; then
	# MCP servers run over stdio; any output emitted before the server starts can break
	# some clients. Default to silencing profile output while still applying env changes.
	GIT_HEX_ENV_SILENCE_PROFILE_OUTPUT="${GIT_HEX_ENV_SILENCE_PROFILE_OUTPUT:-1}"

	if [ -n "${GIT_HEX_ENV_PROFILE:-}" ] && [ -f "${GIT_HEX_ENV_PROFILE}" ]; then
		SHELL_PROFILE="${GIT_HEX_ENV_PROFILE}"
	else
		user_shell="$(basename "${SHELL:-}" 2>/dev/null || echo "")"
		case "${user_shell}" in
		zsh)
			# Prefer profile files that typically contain PATH/version manager setup.
			if [ -f "${HOME}/.zprofile" ]; then
				SHELL_PROFILE="${HOME}/.zprofile"
			elif [ -f "${HOME}/.zshrc" ]; then
				SHELL_PROFILE="${HOME}/.zshrc"
			fi
			;;
		bash)
			if [ -f "${HOME}/.bash_profile" ]; then
				SHELL_PROFILE="${HOME}/.bash_profile"
			elif [ -f "${HOME}/.bashrc" ]; then
				SHELL_PROFILE="${HOME}/.bashrc"
			elif [ -f "${HOME}/.profile" ]; then
				SHELL_PROFILE="${HOME}/.profile"
			fi
			;;
		*)
			# Fallback for other shells: best-effort PATH setup via .profile
			if [ -f "${HOME}/.profile" ]; then
				SHELL_PROFILE="${HOME}/.profile"
			elif [ -f "${HOME}/.zprofile" ]; then
				SHELL_PROFILE="${HOME}/.zprofile"
			elif [ -f "${HOME}/.bash_profile" ]; then
				SHELL_PROFILE="${HOME}/.bash_profile"
			fi
			;;
		esac
	fi

	if [ -n "${SHELL_PROFILE}" ]; then
		if [ "${GIT_HEX_ENV_SILENCE_PROFILE_OUTPUT}" = "1" ]; then
			# shellcheck source=/dev/null
			. "${SHELL_PROFILE}" >/dev/null 2>&1 || true
		else
			# shellcheck source=/dev/null
			. "${SHELL_PROFILE}"
		fi
	fi
fi

# Prefer vendored/framework install locations over whatever happens to be in PATH,
# so the plugin runs on a known-good mcp-bash version.
MCP_BASH=""
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DEFAULT_FRAMEWORK_DIR="${DATA_HOME}/mcp-bash"

if [ -x "${SCRIPT_DIR}/mcp-bash-framework/bin/mcp-bash" ]; then
	MCP_BASH="${SCRIPT_DIR}/mcp-bash-framework/bin/mcp-bash"
elif [ -n "${MCPBASH_HOME:-}" ] && [ -x "${MCPBASH_HOME}/bin/mcp-bash" ]; then
	MCP_BASH="${MCPBASH_HOME}/bin/mcp-bash"
elif [ -x "${DEFAULT_FRAMEWORK_DIR}/bin/mcp-bash" ]; then
	MCP_BASH="${DEFAULT_FRAMEWORK_DIR}/bin/mcp-bash"
elif [ -x "${HOME}/.local/bin/mcp-bash" ]; then
	MCP_BASH="${HOME}/.local/bin/mcp-bash"
elif command -v mcp-bash >/dev/null 2>&1; then
	MCP_BASH="$(command -v mcp-bash)"
fi

if [ -z "${MCP_BASH}" ]; then
	printf 'mcp-bash framework not found.\n' >&2
	printf 'See: https://github.com/yaniv-golan/git-hex/blob/main/docs/install.md\n' >&2
	exit 1
fi

version_ge() {
	# Returns 0 if $1 >= $2 for simple semver "X.Y.Z" (numeric parts only).
	local a="$1" b="$2"
	local a1 a2 a3 b1 b2 b3
	IFS='.' read -r a1 a2 a3 <<<"${a}"
	IFS='.' read -r b1 b2 b3 <<<"${b}"
	a1="${a1:-0}"
	a2="${a2:-0}"
	a3="${a3:-0}"
	b1="${b1:-0}"
	b2="${b2:-0}"
	b3="${b3:-0}"
	if [ "${a1}" -gt "${b1}" ]; then
		return 0
	elif [ "${a1}" -lt "${b1}" ]; then
		return 1
	fi
	if [ "${a2}" -gt "${b2}" ]; then
		return 0
	elif [ "${a2}" -lt "${b2}" ]; then
		return 1
	fi
	[ "${a3}" -ge "${b3}" ]
}

mcp_bash_version_raw="$("${MCP_BASH}" --version 2>/dev/null || true)"
mcp_bash_version="$(printf '%s' "${mcp_bash_version_raw}" | tr -d '\r' | grep -Eo '([0-9]+\\.){2}[0-9]+' | head -n1 || true)"
if [ -n "${mcp_bash_version}" ] && ! version_ge "${mcp_bash_version}" "${REQUIRED_MCPBASH_MIN_VERSION}"; then
	printf 'Error: mcp-bash %s found at %s, but git-hex requires v%s+.\n' "${mcp_bash_version}" "${MCP_BASH}" "${REQUIRED_MCPBASH_MIN_VERSION}" >&2
	printf 'Run ./git-hex.sh to install the pinned framework, or set MCPBASH_HOME to a v%s+ install.\n' "${REQUIRED_MCPBASH_MIN_VERSION}" >&2
	exit 1
fi

export MCPBASH_PROJECT_ROOT="${SCRIPT_DIR}"

# mcp-bash-framework v0.7.0+: tool execution is deny-by-default unless allowlisted.
# The allowlist is exact-match (no globs), so we set the full tool set explicitly.
# Callers can override (e.g., "*" in trusted projects).
if [ -z "${MCPBASH_TOOL_ALLOWLIST:-}" ]; then
	GIT_HEX_TOOL_ALLOWLIST_READONLY="git-hex-getRebasePlan git-hex-checkRebaseConflicts git-hex-getConflictStatus"
	GIT_HEX_TOOL_ALLOWLIST_ALL="git-hex-getRebasePlan git-hex-checkRebaseConflicts git-hex-getConflictStatus git-hex-rebaseWithPlan git-hex-splitCommit git-hex-createFixup git-hex-amendLastCommit git-hex-cherryPickSingle git-hex-resolveConflict git-hex-continueOperation git-hex-abortOperation git-hex-undoLast"
	if [ "${GIT_HEX_READ_ONLY:-}" = "1" ]; then
		export MCPBASH_TOOL_ALLOWLIST="${GIT_HEX_TOOL_ALLOWLIST_READONLY}"
	else
		export MCPBASH_TOOL_ALLOWLIST="${GIT_HEX_TOOL_ALLOWLIST_ALL}"
	fi
fi

exec "${MCP_BASH}" "$@"
