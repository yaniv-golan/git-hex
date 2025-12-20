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
FRAMEWORK_DOCTOR_FIX_MIN_VERSION="0.8.1"

# Wrapper mode flags (parsed for `doctor` only).
GIT_HEX_DOCTOR_MODE="false"
GIT_HEX_DOCTOR_FIX_MODE="false"
GIT_HEX_DOCTOR_DRY_RUN="false"
GIT_HEX_DELEGATE_DOCTOR="false"

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

die() {
	local code="${1:-1}"
	shift || true
	printf '%s\n' "$*" >&2
	exit "${code}"
}

framework_doctor_supports_fix="false"
framework_doctor_supports_dry_run="false"
detect_framework_doctor_caps() {
	if [ ! -x "${framework_bin}" ]; then
		return 0
	fi
	local found_version
	found_version="$(get_mcp_bash_version "${framework_bin}")"
	if [ -n "${found_version}" ] && version_ge "${found_version}" "${FRAMEWORK_DOCTOR_FIX_MIN_VERSION}"; then
		framework_doctor_supports_fix="true"
		framework_doctor_supports_dry_run="true"
		return 0
	fi
	local help
	help="$("${framework_bin}" doctor --help 2>/dev/null || true)"
	case "${help}" in
	*--fix*) framework_doctor_supports_fix="true" ;;
	esac
	case "${help}" in
	*--dry-run*) framework_doctor_supports_dry_run="true" ;;
	esac
}

get_mcp_bash_version() {
	local mcp_bash_bin="$1"
	local raw version
	raw="$("${mcp_bash_bin}" --version 2>/dev/null || true)"
	version="$(printf '%s' "${raw}" | tr -d '\r' | grep -Eo '([0-9]+\.){2}[0-9]+' | head -n1 || true)"
	printf '%s' "${version}"
}

# Parse wrapper-only flags for `doctor` without consuming flags meant for `mcp-bash doctor`.
# Wrapper flags must appear immediately after `doctor`; `--` ends wrapper flag parsing.
if [ "${1:-}" = "doctor" ]; then
	GIT_HEX_DOCTOR_MODE="true"
	framework_bin="${FRAMEWORK_DIR}/bin/mcp-bash"
	detect_framework_doctor_caps
	if [ "${framework_doctor_supports_fix}" = "true" ] || [ "${framework_doctor_supports_dry_run}" = "true" ]; then
		# Framework already supports doctor fix/dry-run. Keep args intact and delegate.
		GIT_HEX_DELEGATE_DOCTOR="true"
	else
		shift
		while [ "$#" -gt 0 ]; do
			case "$1" in
			--fix)
				GIT_HEX_DOCTOR_FIX_MODE="true"
				shift
				;;
			--dry-run)
				GIT_HEX_DOCTOR_DRY_RUN="true"
				shift
				;;
			--)
				shift
				break
				;;
			*)
				break
				;;
			esac
		done
		if [ "${GIT_HEX_DOCTOR_FIX_MODE}" = "true" ] && [ "${GIT_HEX_DOCTOR_DRY_RUN}" = "true" ]; then
			die 2 "ERROR: --fix and --dry-run are mutually exclusive"
		fi
		set -- "doctor" "$@"
	fi
fi

framework_bin="${FRAMEWORK_DIR}/bin/mcp-bash"

doctor_requested_fix="${GIT_HEX_DOCTOR_FIX_MODE}"
if [ "${GIT_HEX_DOCTOR_MODE}" = "true" ] && [ "${doctor_requested_fix}" != "true" ]; then
	for arg in "$@"; do
		if [ "${arg}" = "--fix" ]; then
			doctor_requested_fix="true"
			break
		fi
	done
fi

framework_exists="false"
framework_found_version=""
framework_too_old="false"
if [ -x "${framework_bin}" ]; then
	framework_exists="true"
	framework_found_version="$(get_mcp_bash_version "${framework_bin}")"
	if [ -n "${framework_found_version}" ] && ! version_ge "${framework_found_version}" "${REQUIRED_MCPBASH_MIN_VERSION}"; then
		framework_too_old="true"
	fi
fi

os_name="$(uname -s 2>/dev/null || printf '')"
is_windows_msys() {
	case "${os_name}" in
	MINGW* | MSYS* | CYGWIN*) return 0 ;;
	esac
	return 1
}

symlink_path="${HOME}/.local/bin/mcp-bash"
expected_symlink_target="${FRAMEWORK_DIR}/bin/mcp-bash"

launcher_kind() {
	# On Windows Git Bash/MSYS, symlinks can be fragile (permissions/path normalization).
	# Prefer a simple shim script instead.
	if is_windows_msys; then
		printf '%s' "shim"
	else
		printf '%s' "symlink"
	fi
}

launcher_state() {
	local kind
	kind="$(launcher_kind)"

	if [ "${kind}" = "symlink" ]; then
		if [ -L "${symlink_path}" ]; then
			local target
			target="$(readlink "${symlink_path}" 2>/dev/null || true)"
			if [ -z "${target}" ] || [ ! -e "${symlink_path}" ]; then
				printf '%s' "broken"
				return 0
			fi
			if [ "${target}" = "${expected_symlink_target}" ]; then
				printf '%s' "ok"
				return 0
			fi
			printf '%s' "other"
			return 0
		fi
		if [ -e "${symlink_path}" ]; then
			printf '%s' "not-symlink"
			return 0
		fi
		printf '%s' "missing"
		return 0
	fi

	# shim
	if [ -e "${symlink_path}" ]; then
		if [ -f "${symlink_path}" ] && [ -x "${symlink_path}" ]; then
			if grep -F "${expected_symlink_target}" "${symlink_path}" >/dev/null 2>&1; then
				printf '%s' "ok"
				return 0
			fi
			printf '%s' "other"
			return 0
		fi
		printf '%s' "not-file"
		return 0
	fi
	printf '%s' "missing"
	return 0
}

ensure_launcher() {
	local kind
	kind="$(launcher_kind)"

	mkdir -p "${HOME}/.local/bin"

	if [ -d "${symlink_path}" ]; then
		die 2 "ERROR: Cannot create launcher at ${symlink_path}: path is a directory"
	fi

	if [ "${kind}" = "symlink" ]; then
		if ln -snf "${expected_symlink_target}" "${symlink_path}" 2>/dev/null; then
			return 0
		fi
		# Fallback: if symlinks fail, create a shim script.
		kind="shim"
	fi

	local tmp
	tmp="$(mktemp "${HOME}/.local/bin/mcp-bash.tmp.XXXXXX")"
	cat >"${tmp}" <<EOF
#!/usr/bin/env bash
exec "${expected_symlink_target}" "\$@"
EOF
	chmod +x "${tmp}"
	mv "${tmp}" "${symlink_path}"
}

print_doctor_missing_framework() {
	printf '%s\n' "ERROR: MCP Bash Framework not found at ${FRAMEWORK_DIR}" >&2
	printf '%s\n' "" >&2
	printf '%s\n' "To install/repair, run:" >&2
	printf '%s\n' "  ./git-hex.sh doctor --fix" >&2
	printf '%s\n' "" >&2
	printf '%s\n' "If you manage your own framework install, set MCPBASH_HOME and re-run:" >&2
	printf '%s\n' "  MCPBASH_HOME=/path/to/mcp-bash ./git-hex.sh doctor" >&2
}

print_doctor_framework_too_old() {
	printf '%s\n' "ERROR: mcp-bash ${framework_found_version:-unknown} found at ${FRAMEWORK_DIR}, but git-hex requires v${REQUIRED_MCPBASH_MIN_VERSION}+." >&2
	printf '%s\n' "" >&2
	if [ "${FRAMEWORK_DIR}" = "${DEFAULT_FRAMEWORK_DIR}" ]; then
		printf '%s\n' "To upgrade/repair, run:" >&2
		printf '%s\n' "  ./git-hex.sh doctor --fix" >&2
	else
		printf '%s\n' "Upgrade that install manually, or unset MCPBASH_HOME to use the managed default (${DEFAULT_FRAMEWORK_DIR})." >&2
	fi
}

print_doctor_dry_run_actions() {
	local state kind
	kind="$(launcher_kind)"
	state="$(launcher_state)"

	if [ "${framework_exists}" != "true" ]; then
		printf '%s\n' "Would install framework ${FRAMEWORK_VERSION} into ${FRAMEWORK_DIR}"
	elif [ "${framework_too_old}" = "true" ]; then
		printf '%s\n' "Would upgrade framework at ${FRAMEWORK_DIR} from ${framework_found_version:-unknown} to ${FRAMEWORK_VERSION}"
	else
		printf '%s\n' "No framework install/upgrade needed (found ${framework_found_version:-unknown} at ${FRAMEWORK_DIR})"
	fi

	if [ "${FRAMEWORK_DIR}" = "${DEFAULT_FRAMEWORK_DIR}" ]; then
		if [ "${kind}" = "symlink" ]; then
			case "${state}" in
			ok) printf '%s\n' "Launcher OK (symlink): ${symlink_path} -> ${expected_symlink_target}" ;;
			missing) printf '%s\n' "Would create launcher (symlink): ${symlink_path} -> ${expected_symlink_target}" ;;
			broken) printf '%s\n' "Would repair launcher (symlink): ${symlink_path} -> ${expected_symlink_target}" ;;
			other) printf '%s\n' "Would replace launcher (symlink): ${symlink_path} -> ${expected_symlink_target}" ;;
			not-symlink) printf '%s\n' "Would replace non-symlink at ${symlink_path} with launcher (symlink) to ${expected_symlink_target}" ;;
			esac
		else
			case "${state}" in
			ok) printf '%s\n' "Launcher OK (shim): ${symlink_path} (execs ${expected_symlink_target})" ;;
			missing) printf '%s\n' "Would create launcher (shim): ${symlink_path} (execs ${expected_symlink_target})" ;;
			other) printf '%s\n' "Would replace launcher (shim): ${symlink_path} (execs ${expected_symlink_target})" ;;
			not-file) printf '%s\n' "Would replace non-file at ${symlink_path} with launcher (shim) to ${expected_symlink_target}" ;;
			esac
		fi
	else
		printf '%s\n' "Would NOT modify ${symlink_path} (framework path is user-managed: ${FRAMEWORK_DIR})"
	fi
}

# Wrapper-mode read-only doctor / dry-run behavior: no installs, no upgrades, no launcher changes.
# If the framework supports doctor fix/dry-run, delegate that behavior to `mcp-bash doctor`.
if [ "${GIT_HEX_DOCTOR_MODE}" = "true" ] && [ "${GIT_HEX_DELEGATE_DOCTOR}" != "true" ] && [ "${GIT_HEX_DOCTOR_FIX_MODE}" != "true" ]; then
	if [ "${GIT_HEX_DOCTOR_DRY_RUN}" = "true" ]; then
		print_doctor_dry_run_actions
		if [ "${framework_exists}" != "true" ] || [ "${framework_too_old}" = "true" ]; then
			exit 1
		fi
		# Framework exists and is sufficiently new; run `mcp-bash doctor` normally.
	else
		if [ "${framework_exists}" != "true" ]; then
			print_doctor_missing_framework
			exit 1
		fi
		if [ "${framework_too_old}" = "true" ]; then
			print_doctor_framework_too_old
			exit 1
		fi
	fi
fi

if [ "${GIT_HEX_DELEGATE_DOCTOR}" != "true" ]; then
	if [ "${GIT_HEX_DOCTOR_MODE}" = "true" ] && [ "${GIT_HEX_DOCTOR_FIX_MODE}" = "true" ] && [ -n "${MCPBASH_HOME:-}" ]; then
		# In wrapper-mode, treat user-managed installs as unsupported fix targets.
		# Future framework versions may return a distinct policy refusal code (e.g. 3).
		die 3 "ERROR: doctor --fix does not modify MCPBASH_HOME-managed installs (${FRAMEWORK_DIR}). Unset MCPBASH_HOME to use the managed default (${DEFAULT_FRAMEWORK_DIR}), or upgrade that install manually."
	fi

	if [ "${GIT_HEX_DOCTOR_MODE}" = "true" ] && [ "${GIT_HEX_DOCTOR_FIX_MODE}" = "true" ] && [ "${FRAMEWORK_DIR}" != "${DEFAULT_FRAMEWORK_DIR}" ]; then
		die 3 "ERROR: doctor --fix only operates on the managed default install path (${DEFAULT_FRAMEWORK_DIR}); current framework path is ${FRAMEWORK_DIR}."
	fi
fi

# Refuse to auto-upgrade user-managed framework locations.
if [ "${framework_too_old}" = "true" ] && [ "${FRAMEWORK_DIR}" != "${DEFAULT_FRAMEWORK_DIR}" ]; then
	# For `doctor`, the error is handled above; this protects non-doctor commands.
	echo "mcp-bash ${framework_found_version:-unknown} found at ${FRAMEWORK_DIR}, but git-hex requires v${REQUIRED_MCPBASH_MIN_VERSION}+." >&2
	echo "Upgrade that install manually, or unset MCPBASH_HOME to use the managed default (${DEFAULT_FRAMEWORK_DIR})." >&2
	exit 1
fi

ensure_safe_target_dir() {
	local target_dir="$1"
	if [ -z "${target_dir}" ] || [ "${target_dir}" = "/" ]; then
		die 2 "Refusing to operate on unsafe target dir path: ${target_dir}"
	fi
}

atomic_replace_dir() {
	local staging_dir="$1"
	local target_dir="$2"
	local backup_dir=""

	ensure_safe_target_dir "${target_dir}"

	if [ ! -d "${staging_dir}" ]; then
		die 2 "Internal error: staging dir missing: ${staging_dir}"
	fi

	if [ -e "${target_dir}" ]; then
		backup_dir="${target_dir}.bak.$(date +%s)"
		mv "${target_dir}" "${backup_dir}"
	fi

	if mv "${staging_dir}" "${target_dir}"; then
		if [ -n "${backup_dir}" ] && [ -e "${backup_dir}" ]; then
			rm -rf "${backup_dir}" || true
		fi
		return 0
	fi

	# Restore on failure.
	if [ -n "${backup_dir}" ] && [ -e "${backup_dir}" ]; then
		rm -rf "${target_dir}" 2>/dev/null || true
		mv "${backup_dir}" "${target_dir}" 2>/dev/null || true
	fi
	die 2 "Failed to replace ${target_dir} with staged install; re-run doctor --fix to retry."
}

install_from_verified_archive() {
	local version="$1"
	local target_dir="$2"
	local sha_expected="${3:-}"
	local archive_url="${4:-}"

	if [ -z "${sha_expected}" ]; then
		return 1
	fi

	if [ -z "${archive_url}" ]; then
		# Default to the GitHub tag archive (always available for tags). Override via GIT_HEX_MCPBASH_ARCHIVE_URL if needed.
		archive_url="https://github.com/yaniv-golan/mcp-bash-framework/archive/refs/tags/${version}.tar.gz"
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

	echo "Checksum verified; extracting..." >&2
	ensure_safe_target_dir "${target_dir}"
	mkdir -p "${target_dir%/*}"

	local staging_dir
	staging_dir="$(mktemp -d "${target_dir%/*}/mcp-bash.stage.XXXXXX")"
	if [ -z "${staging_dir}" ] || [ ! -d "${staging_dir}" ]; then
		echo "Failed to allocate staging dir for install" >&2
		rm -f "${tmp_archive}" || true
		return 1
	fi

	if ! tar -xzf "${tmp_archive}" -C "${staging_dir}" --strip-components 1; then
		echo "Failed to extract archive" >&2
		rm -f "${tmp_archive}" || true
		rm -rf "${staging_dir}" || true
		return 1
	fi
	rm -f "${tmp_archive}" || true

	if [ ! -x "${staging_dir}/bin/mcp-bash" ]; then
		echo "Extracted archive does not contain an executable bin/mcp-bash" >&2
		rm -rf "${staging_dir}" || true
		return 1
	fi

	atomic_replace_dir "${staging_dir}" "${target_dir}"
	return 0
}

# Auto-install framework if missing, unless disabled
if [ "${framework_exists}" != "true" ] || [ "${framework_too_old}" = "true" ]; then
	if [ "${GIT_HEX_AUTO_INSTALL_FRAMEWORK:-true}" != "true" ]; then
		echo "mcp-bash framework not found at ${FRAMEWORK_DIR}. Set MCPBASH_HOME to an existing install or enable auto-install (GIT_HEX_AUTO_INSTALL_FRAMEWORK=true)." >&2
		exit 1
	fi
	if [ "${GIT_HEX_DOCTOR_MODE}" = "true" ] && [ "${doctor_requested_fix}" != "true" ]; then
		# Read-only doctor is handled above; this is a safety net.
		print_doctor_missing_framework
		exit 1
	fi
	echo "Installing mcp-bash framework ${FRAMEWORK_VERSION} into ${FRAMEWORK_DIR}..." >&2
	ensure_safe_target_dir "${FRAMEWORK_DIR}"
	mkdir -p "${FRAMEWORK_DIR%/*}"
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
			staging_dir="$(mktemp -d "${FRAMEWORK_DIR%/*}/mcp-bash.stage.XXXXXX")"
			if [ -z "${staging_dir}" ] || [ ! -d "${staging_dir}" ]; then
				echo "Failed to allocate staging dir for install" >&2
				exit 1
			fi
			git init "${staging_dir}"
			git -C "${staging_dir}" -c fetch.fsckobjects=true -c transfer.fsckobjects=true remote add origin \
				https://github.com/yaniv-golan/mcp-bash-framework.git
			git -C "${staging_dir}" -c fetch.fsckobjects=true -c transfer.fsckobjects=true fetch --depth 1 origin "${expected_git_sha}"
			git -C "${staging_dir}" checkout --detach FETCH_HEAD
			actual_git_sha="$(git -C "${staging_dir}" rev-parse HEAD 2>/dev/null || true)"
			if [ "${actual_git_sha}" != "${expected_git_sha}" ]; then
				rm -rf "${staging_dir}" || true
				echo "Unexpected mcp-bash-framework revision: ${actual_git_sha} (expected ${expected_git_sha})" >&2
				exit 1
			fi
			atomic_replace_dir "${staging_dir}" "${FRAMEWORK_DIR}"
		else
			staging_dir="$(mktemp -d "${FRAMEWORK_DIR%/*}/mcp-bash.stage.XXXXXX")"
			if [ -z "${staging_dir}" ] || [ ! -d "${staging_dir}" ]; then
				echo "Failed to allocate staging dir for install" >&2
				exit 1
			fi
			git -c fetch.fsckobjects=true -c transfer.fsckobjects=true clone --depth 1 --branch "${FRAMEWORK_VERSION}" \
				https://github.com/yaniv-golan/mcp-bash-framework.git "${staging_dir}"
			atomic_replace_dir "${staging_dir}" "${FRAMEWORK_DIR}"
		fi
	fi
	# Create a convenience symlink matching the installer behavior
	if [ "${GIT_HEX_DOCTOR_MODE}" != "true" ] || [ "${GIT_HEX_DOCTOR_FIX_MODE}" = "true" ]; then
		ensure_launcher
	fi
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
