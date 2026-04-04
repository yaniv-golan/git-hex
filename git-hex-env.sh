#!/usr/bin/env bash
set -euo pipefail

# Launcher for macOS apps (e.g., Claude Desktop) that may not inherit your Terminal
# environment (PATH/version managers). It sources your login profile files before
# starting the server so tool discovery matches your Terminal setup.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Debug Mode
# ==============================================================================
if [[ "${GIT_HEX_DEBUG:-}" == "1" ]]; then
	export MCPBASH_LOG_LEVEL="${MCPBASH_LOG_LEVEL:-debug}"
fi

# Cache version at startup (for debug banner)
GIT_HEX_VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "unknown")

SHELL_PROFILE=""

if [ "${GIT_HEX_ENV_NO_PROFILE:-}" != "1" ]; then
	# MCP servers run over stdio; any output emitted before the server starts can break
	# some clients. Default to silencing profile output while still applying env changes.
	GIT_HEX_ENV_SILENCE_PROFILE_OUTPUT="${GIT_HEX_ENV_SILENCE_PROFILE_OUTPUT:-1}"

	if [ -n "${GIT_HEX_ENV_PROFILE:-}" ] && [ -f "${GIT_HEX_ENV_PROFILE}" ]; then
		SHELL_PROFILE="${GIT_HEX_ENV_PROFILE}"
	else
		user_shell="$(basename "${SHELL:-}" 2>/dev/null || echo "")"
		SHELL_PROFILE_EXTRA=""
		case "${user_shell}" in
		zsh)
			# Source both login (.zprofile) and interactive (.zshrc) profiles.
			# Many tools like pyenv, nvm, rbenv are configured in .zshrc.
			if [ -f "${HOME}/.zprofile" ]; then
				SHELL_PROFILE="${HOME}/.zprofile"
			fi
			if [ -f "${HOME}/.zshrc" ]; then
				SHELL_PROFILE_EXTRA="${HOME}/.zshrc"
			fi
			;;
		bash)
			# Source both login (.bash_profile) and interactive (.bashrc) profiles.
			if [ -f "${HOME}/.bash_profile" ]; then
				SHELL_PROFILE="${HOME}/.bash_profile"
			elif [ -f "${HOME}/.profile" ]; then
				SHELL_PROFILE="${HOME}/.profile"
			fi
			if [ -f "${HOME}/.bashrc" ]; then
				SHELL_PROFILE_EXTRA="${HOME}/.bashrc"
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

	# Source primary profile
	if [ -n "${SHELL_PROFILE}" ]; then
		if [ "${GIT_HEX_ENV_SILENCE_PROFILE_OUTPUT}" = "1" ]; then
			# shellcheck source=/dev/null
			. "${SHELL_PROFILE}" >/dev/null 2>&1 || true
		else
			# shellcheck source=/dev/null
			. "${SHELL_PROFILE}"
		fi
	fi

	# Source secondary profile (interactive shell config with version managers)
	if [ -n "${SHELL_PROFILE_EXTRA:-}" ]; then
		if [ "${GIT_HEX_ENV_SILENCE_PROFILE_OUTPUT}" = "1" ]; then
			# shellcheck source=/dev/null
			. "${SHELL_PROFILE_EXTRA}" >/dev/null 2>&1 || true
		else
			# shellcheck source=/dev/null
			. "${SHELL_PROFILE_EXTRA}"
		fi
	fi
fi

# ==============================================================================
# Vendored Runtime
# ==============================================================================
FRAMEWORK_DIR="${SCRIPT_DIR}/.mcp-bash"

if [ ! -x "${FRAMEWORK_DIR}/bin/mcp-bash" ]; then
	printf 'Vendored mcp-bash runtime not found at %s\n' "${FRAMEWORK_DIR}" >&2
	printf 'Try: git checkout -- .mcp-bash/\n' >&2
	exit 1
fi

export MCPBASH_PROJECT_ROOT="${SCRIPT_DIR}"

# Tool allowlist
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
	echo "[git-hex:${GIT_HEX_VERSION}] Debug mode enabled (via git-hex-env.sh)" >&2
	echo "[git-hex:${GIT_HEX_VERSION}] Versions: git-hex=${GIT_HEX_VERSION} mcp-bash=v${VENDOR_VERSION}" >&2
	echo "[git-hex:${GIT_HEX_VERSION}] Process: pid=$$ started=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)" >&2
fi

exec "${FRAMEWORK_DIR}/bin/mcp-bash" "$@"
