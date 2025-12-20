#!/usr/bin/env bash
# Backup ref management for git-hex undo functionality
#
# Creates refs/git-hex/backup/<timestamp>_<operation>_<unique> before mutating operations
# and maintains refs/git-hex/last/<timestamp>_<operation>_<unique> pointing to the most recent backup.

set -euo pipefail

# Namespace for all git-hex refs
GIT_HEX_REF_PREFIX="refs/git-hex"

# Create a backup ref before a mutating operation
# Usage: git_hex_create_backup <repo_path> <operation_name>
# Returns: The backup ref name (without refs/ prefix)
git_hex_create_backup() {
	local repo_path="$1"
	local operation="$2"

	local head_hash
	head_hash="$(git -C "${repo_path}" rev-parse HEAD)"

	local git_dir
	git_dir="$(git -C "${repo_path}" rev-parse --git-dir)"

	local timestamp
	timestamp="$(date +%s)"

	# Add a uniqueness suffix (PID + RANDOM) to avoid collisions within the same second.
	local uniq_suffix
	# Unique suffix has no underscores to keep parsing simple: <operation>_<unique>
	uniq_suffix="${timestamp}_${operation}_$$${RANDOM:-0}"

	local backup_ref="${GIT_HEX_REF_PREFIX}/backup/${uniq_suffix}"

	# Create the backup ref pointing to current HEAD
	git -C "${repo_path}" update-ref "${backup_ref}" "${head_hash}"

	# Also update a "last" pointer that includes the operation name
	# Format: refs/git-hex/last/<timestamp>_<operation>_<unique>
	# Create the new "last" ref first so there is no window where no "last" ref exists.
	last_ref="${GIT_HEX_REF_PREFIX}/last/${uniq_suffix}"
	git -C "${repo_path}" update-ref "${last_ref}" "${head_hash}"

	# Then, delete any other existing "last" refs
	while IFS= read -r ref; do
		[ -n "${ref}" ] || continue
		[ "${ref}" = "${last_ref}" ] && continue
		delete_err=""
		if ! delete_err="$(git -C "${repo_path}" update-ref -d "${ref}" 2>&1)"; then
			# Non-fatal, but important to surface (e.g., locked ref / permissions).
			if command -v mcp_log >/dev/null 2>&1; then
				mcp_log "warn" "git-hex" "$(printf '{"message":"Failed to delete ref %s: %s"}' "${ref}" "${delete_err}")"
			elif command -v mcp_log_warn >/dev/null 2>&1; then
				mcp_log_warn "git-hex" "$(printf '{"message":"Failed to delete ref %s: %s"}' "${ref}" "${delete_err}")"
			fi
		fi
	done < <(git -C "${repo_path}" for-each-ref --format='%(refname)' "${GIT_HEX_REF_PREFIX}/last/" 2>/dev/null || true)

	# Track the last backup ref for subsequent state recording
	GIT_HEX_LAST_BACKUP_REF="git-hex/backup/${uniq_suffix}"

	# Persist the last backup suffix so future invocations can record last-head safely
	printf '%s\n' "${uniq_suffix}" >"${git_dir}/git-hex-last-backup" 2>/dev/null || true

	# Return the ref name (without refs/ prefix for display)
	echo "git-hex/backup/${uniq_suffix}"
}

# Get the most recent backup info
# Usage: git_hex_get_last_backup <repo_path>
# Returns: pipe-separated string: hash|operation|timestamp|backup_ref
git_hex_get_last_backup() {
	local repo_path="$1"

	# Find the most recent "last" ref (there should only be one)
	local last_ref
	last_ref="$(git -C "${repo_path}" for-each-ref --sort=-creatordate --format='%(refname)' "${GIT_HEX_REF_PREFIX}/last/" 2>/dev/null | head -1 || echo "")"

	if [ -z "${last_ref}" ]; then
		echo ""
		return 0
	fi

	local backup_hash
	backup_hash="$(git -C "${repo_path}" rev-parse "${last_ref}" 2>/dev/null || echo "")"

	if [ -z "${backup_hash}" ]; then
		echo ""
		return 0
	fi

	# Extract operation name, timestamp, and unique suffix from ref name
	# Format: refs/git-hex/last/<timestamp>_<operation>_<unique>
	local ref_basename
	ref_basename="${last_ref##*/}" # Get just the "timestamp_operation_unique" part

	local timestamp=""
	local operation=""
	# Parse timestamp_operation_unique format using parameter expansion (more portable than regex)
	if [[ "${ref_basename}" == *_* ]]; then
		timestamp="${ref_basename%%_*}" # Everything before first underscore
		local rest
		rest="${ref_basename#*_}" # operation_unique
		if [[ "${rest}" == *_* ]]; then
			operation="${rest%_*}" # drop trailing _unique
		else
			operation="${rest}"
		fi
	fi

	# Find the corresponding backup ref
	local backup_ref=""
	if [ -n "${timestamp}" ] && [ -n "${operation}" ]; then
		# Prefer an exact match to the last ref chosen above (including unique suffix)
		local suffix="${ref_basename}"
		local expected_ref="${GIT_HEX_REF_PREFIX}/backup/${suffix}"
		if git -C "${repo_path}" show-ref --verify --quiet "${expected_ref}" 2>/dev/null; then
			backup_ref="git-hex/backup/${suffix}"
		fi
	fi

	# Fallback: pick most recent backup if the expected ref is missing
	if [ -z "${backup_ref}" ]; then
		backup_ref="$(git -C "${repo_path}" for-each-ref --sort=-creatordate --format='%(refname:short)' "${GIT_HEX_REF_PREFIX}/backup/" 2>/dev/null | head -1 || echo "")"
	fi

	echo "${backup_hash}|${operation}|${timestamp}|${backup_ref}"
}

# Record the HEAD after a mutating operation for undo safety checks
# Uses the most recent backup ref metadata captured in GIT_HEX_LAST_BACKUP_REF.
git_hex_record_last_head() {
	local repo_path="$1"
	local head_after="${2:-}"

	local suffix=""
	if [ -n "${GIT_HEX_LAST_BACKUP_REF:-}" ]; then
		suffix="${GIT_HEX_LAST_BACKUP_REF#git-hex/backup/}"
	else
		local git_dir
		git_dir="$(git -C "${repo_path}" rev-parse --git-dir 2>/dev/null || true)"
		if [ -n "${git_dir}" ] && [ -f "${git_dir}/git-hex-last-backup" ]; then
			suffix="$(head -1 "${git_dir}/git-hex-last-backup" 2>/dev/null | tr -d '\r\n')"
		fi
		if [ -z "${suffix}" ]; then
			# As a fallback, derive from the most recent backup ref
			local backup_info
			backup_info="$(git_hex_get_last_backup "${repo_path}")"
			if [ -n "${backup_info}" ]; then
				IFS='|' read -r _ op ts ref <<<"${backup_info}"
				if [ -n "${ref}" ]; then
					suffix="${ref#git-hex/backup/}"
				elif [ -n "${ts}" ] && [ -n "${op}" ]; then
					suffix="${ts}_${op}"
				fi
			fi
		fi
	fi
	if [ -z "${suffix}" ]; then
		return 0
	fi
	GIT_HEX_LAST_BACKUP_REF="git-hex/backup/${suffix}"
	if [ -z "${head_after}" ]; then
		head_after="$(git -C "${repo_path}" rev-parse HEAD 2>/dev/null || true)"
	fi
	if [ -z "${head_after}" ]; then
		return 0
	fi

	git -C "${repo_path}" update-ref "${GIT_HEX_REF_PREFIX}/last-head/${suffix}" "${head_after}" 2>/dev/null || true

	# Opportunistically prune old backups to keep ref space tidy
	git_hex_cleanup_backups "${repo_path}" 20
}

# List all backup refs
# Usage: git_hex_list_backups <repo_path> [limit]
# Returns: List of backup refs with metadata
git_hex_list_backups() {
	local repo_path="$1"
	local limit="${2:-10}"

	git -C "${repo_path}" for-each-ref \
		--sort=-creatordate \
		--count="${limit}" \
		--format='%(refname:short)|%(objectname:short)|%(creatordate:iso)' \
		"${GIT_HEX_REF_PREFIX}/backup/" 2>/dev/null || echo ""
}

# Clean up old backup refs (keep last N)
# Usage: git_hex_cleanup_backups <repo_path> [keep_count]
git_hex_cleanup_backups() {
	local repo_path="$1"
	local keep_count="${2:-20}"

	local refs_to_delete
	refs_to_delete="$(git -C "${repo_path}" for-each-ref \
		--sort=-creatordate \
		--format='%(refname)' \
		"${GIT_HEX_REF_PREFIX}/backup/" 2>/dev/null | tail -n +$((keep_count + 1)))"

	while IFS= read -r ref; do
		[ -n "${ref}" ] || continue
		git -C "${repo_path}" update-ref -d "${ref}" 2>/dev/null || true
	done <<<"${refs_to_delete}"
}
