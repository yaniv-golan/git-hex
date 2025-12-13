#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Framework version pinning for reproducible installs
# Update this when upgrading to a new framework version
FRAMEWORK_VERSION="${MCPBASH_VERSION:-v0.7.0}"

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

# Respect a vendored framework if present
if [ -x "${SCRIPT_DIR}/mcp-bash-framework/bin/mcp-bash" ]; then
	FRAMEWORK_DIR="${SCRIPT_DIR}/mcp-bash-framework"
fi

install_from_verified_archive() {
	local version="$1"
	local target_dir="$2"
	local sha_expected="${3:-}"
	local archive_url="${4:-}"

	if [ -z "${sha_expected}" ]; then
		return 1
	fi

	if [ -z "${archive_url}" ]; then
		# v0.7.0+: verification is published for the release tarball + SHA256SUMS.
		archive_url="https://github.com/yaniv-golan/mcp-bash-framework/releases/download/${version}/mcp-bash-${version}.tar.gz"
	fi

	local tmp_archive
	tmp_archive="$(mktemp "${TMPDIR:-/tmp}/mcpbash.${version}.XXXXXX.tar.gz")"
	if [ -z "${tmp_archive}" ]; then
		echo "Failed to allocate temp archive path" >&2
		return 1
	fi

	echo "Downloading verified archive ${archive_url}..." >&2
	if ! curl -fsSL "${archive_url}" -o "${tmp_archive}"; then
		echo "Failed to download ${archive_url}" >&2
		rm -f "${tmp_archive}" || true
		return 1
	fi

	local sha_actual=""
	if command -v sha256sum >/dev/null 2>&1; then
		sha_actual="$(sha256sum "${tmp_archive}" | awk '{print $1}')"
	elif command -v shasum >/dev/null 2>&1; then
		sha_actual="$(shasum -a 256 "${tmp_archive}" | awk '{print $1}')"
	else
		echo "sha256sum/shasum not available for verification" >&2
		rm -f "${tmp_archive}" || true
		return 1
	fi

	if [ "${sha_actual}" != "${sha_expected}" ]; then
		echo "Checksum mismatch for ${archive_url}. Expected ${sha_expected}, got ${sha_actual}" >&2
		rm -f "${tmp_archive}" || true
		return 1
	fi

	echo "Checksum verified; extracting to ${target_dir}..." >&2
	mkdir -p "${target_dir}"
	if ! tar -xzf "${tmp_archive}" -C "${target_dir}" --strip-components 1; then
		echo "Failed to extract archive" >&2
		rm -f "${tmp_archive}" || true
		return 1
	fi
	rm -f "${tmp_archive}" || true
	return 0
}

# Auto-install framework if missing, unless disabled
if [ ! -x "${FRAMEWORK_DIR}/bin/mcp-bash" ]; then
	if [ "${GIT_HEX_AUTO_INSTALL_FRAMEWORK:-true}" != "true" ]; then
		echo "mcp-bash framework not found at ${FRAMEWORK_DIR}. Set MCPBASH_HOME to an existing install or enable auto-install (GIT_HEX_AUTO_INSTALL_FRAMEWORK=true)." >&2
		exit 1
	fi
	echo "Installing mcp-bash framework ${FRAMEWORK_VERSION} into ${FRAMEWORK_DIR}..." >&2
	mkdir -p "${FRAMEWORK_DIR%/*}"
	if [ -n "${GIT_HEX_MCPBASH_SHA256:-}" ]; then
		install_from_verified_archive "${FRAMEWORK_VERSION}" "${FRAMEWORK_DIR}" "${GIT_HEX_MCPBASH_SHA256}" "${GIT_HEX_MCPBASH_ARCHIVE_URL:-}" || {
			echo "Verified archive install failed; aborting." >&2
			exit 1
		}
	else
		git clone --depth 1 --branch "${FRAMEWORK_VERSION}" \
			https://github.com/yaniv-golan/mcp-bash-framework.git "${FRAMEWORK_DIR}"
	fi
	# Create a convenience symlink matching the installer behavior
	mkdir -p "$HOME/.local/bin"
	ln -snf "${FRAMEWORK_DIR}/bin/mcp-bash" "$HOME/.local/bin/mcp-bash"
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

exec "${FRAMEWORK_DIR}/bin/mcp-bash" "$@"
