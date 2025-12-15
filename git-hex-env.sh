#!/usr/bin/env bash
set -euo pipefail

# Login-aware launcher for GUI clients (e.g., macOS Claude Desktop) where PATH
# and version managers are only set in your shell profile.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
			# Login shells typically source .zprofile; interactive shells source .zshrc.
			# Prefer login profile first so PATH/version managers are set for GUI apps.
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
	printf "Install (recommended, verified): set GIT_HEX_MCPBASH_SHA256 to the published checksum for v0.8.0, then run ./git-hex.sh (it will download + verify the release tarball).\n" >&2
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
