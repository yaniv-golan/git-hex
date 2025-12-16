#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Framework version pinning for reproducible installs
# Update this when upgrading to a new framework version
FRAMEWORK_VERSION="${MCPBASH_VERSION:-v0.8.0}"
FRAMEWORK_VERSION_DEFAULT="v0.8.0"
# Pinned commit for v0.8.0 installs (annotated tags have distinct object SHAs).
FRAMEWORK_GIT_SHA_DEFAULT_V080="b2737e20ee52af1067a19f3ea88e81c47aa34a6d"
REQUIRED_MCPBASH_MIN_VERSION="0.8.0"

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

get_mcp_bash_version() {
	local mcp_bash_bin="$1"
	local raw version
	raw="$("${mcp_bash_bin}" --version 2>/dev/null || true)"
	version="$(printf '%s' "${raw}" | tr -d '\r' | grep -Eo '([0-9]+\\.){2}[0-9]+' | head -n1 || true)"
	printf '%s' "${version}"
}

ensure_min_framework_version_or_install() {
	# If an existing install is too old, upgrade in-place only for the default XDG dir.
	# For explicit MCPBASH_HOME/vendored installs, fail with instructions instead.
	if [ ! -x "${FRAMEWORK_DIR}/bin/mcp-bash" ]; then
		return 0
	fi

	local found_version
	found_version="$(get_mcp_bash_version "${FRAMEWORK_DIR}/bin/mcp-bash")"
	if [ -z "${found_version}" ]; then
		return 0
	fi
	if version_ge "${found_version}" "${REQUIRED_MCPBASH_MIN_VERSION}"; then
		return 0
	fi

	if [ "${FRAMEWORK_DIR}" != "${DEFAULT_FRAMEWORK_DIR}" ]; then
		echo "mcp-bash ${found_version} found at ${FRAMEWORK_DIR}, but git-hex requires v${REQUIRED_MCPBASH_MIN_VERSION}+." >&2
		echo "Upgrade your mcp-bash install or set MCPBASH_HOME to a v${REQUIRED_MCPBASH_MIN_VERSION}+ install (recommended: run ./git-hex.sh without MCPBASH_HOME to auto-install the pinned framework)." >&2
		exit 1
	fi

	echo "Upgrading mcp-bash ${found_version} at ${FRAMEWORK_DIR} to ${FRAMEWORK_VERSION} (git-hex requires v${REQUIRED_MCPBASH_MIN_VERSION}+)..." >&2
	if [ -z "${FRAMEWORK_DIR}" ] || [ "${FRAMEWORK_DIR}" = "/" ]; then
		echo "Refusing to remove unsafe framework dir path: ${FRAMEWORK_DIR}" >&2
		exit 1
	fi
	rm -rf "${FRAMEWORK_DIR}"
}

ensure_min_framework_version_or_install

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
	# BSD/macOS `mktemp` requires the XXXXXX template to be at the end of the path.
	tmp_archive="$(mktemp "${TMPDIR:-/tmp}/mcpbash.${version}.XXXXXX")"
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
	if [ -z "${target_dir}" ] || [ "${target_dir}" = "/" ]; then
		echo "Refusing to extract to unsafe target dir path: ${target_dir}" >&2
		rm -f "${tmp_archive}" || true
		return 1
	fi
	rm -rf "${target_dir}"
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
	rm -rf "${FRAMEWORK_DIR}"
	if [ -n "${GIT_HEX_MCPBASH_SHA256:-}" ]; then
		install_from_verified_archive "${FRAMEWORK_VERSION}" "${FRAMEWORK_DIR}" "${GIT_HEX_MCPBASH_SHA256}" "${GIT_HEX_MCPBASH_ARCHIVE_URL:-}" || {
			echo "Verified archive install failed; aborting." >&2
			exit 1
		}
	else
		expected_git_sha="${GIT_HEX_MCPBASH_GIT_SHA:-}"
		if [ -z "${expected_git_sha}" ] && [ "${FRAMEWORK_VERSION}" = "${FRAMEWORK_VERSION_DEFAULT}" ]; then
			expected_git_sha="${FRAMEWORK_GIT_SHA_DEFAULT_V080}"
		fi
		if [ -z "${expected_git_sha}" ] && [ "${GIT_HEX_ALLOW_UNVERIFIED_FRAMEWORK:-}" != "true" ]; then
			echo "Refusing to auto-install an unverified mcp-bash framework." >&2
			echo "Set GIT_HEX_MCPBASH_SHA256 (preferred) or GIT_HEX_MCPBASH_GIT_SHA to enable verified installs." >&2
			echo "To bypass (not recommended), set GIT_HEX_ALLOW_UNVERIFIED_FRAMEWORK=true." >&2
			exit 1
		fi
		if [ -n "${expected_git_sha}" ]; then
			git init "${FRAMEWORK_DIR}"
			git -C "${FRAMEWORK_DIR}" -c fetch.fsckobjects=true -c transfer.fsckobjects=true remote add origin \
				https://github.com/yaniv-golan/mcp-bash-framework.git
			git -C "${FRAMEWORK_DIR}" -c fetch.fsckobjects=true -c transfer.fsckobjects=true fetch --depth 1 origin "${expected_git_sha}"
			git -C "${FRAMEWORK_DIR}" checkout --detach FETCH_HEAD
			actual_git_sha="$(git -C "${FRAMEWORK_DIR}" rev-parse HEAD 2>/dev/null || true)"
			if [ "${actual_git_sha}" != "${expected_git_sha}" ]; then
				echo "Unexpected mcp-bash-framework revision: ${actual_git_sha} (expected ${expected_git_sha})" >&2
				exit 1
			fi
		else
			git -c fetch.fsckobjects=true -c transfer.fsckobjects=true clone --depth 1 --branch "${FRAMEWORK_VERSION}" \
				https://github.com/yaniv-golan/mcp-bash-framework.git "${FRAMEWORK_DIR}"
		fi
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
