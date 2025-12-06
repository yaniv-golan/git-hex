#!/usr/bin/env bash
# Backup ref management for git-hex undo functionality
#
# Creates refs/git-hex/backup/<timestamp>_<operation> before mutating operations
# and maintains refs/git-hex/last-<operation> pointing to the most recent backup.

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

	local timestamp
	timestamp="$(date +%s)"

	local backup_ref="${GIT_HEX_REF_PREFIX}/backup/${timestamp}_${operation}"

	# Create the backup ref pointing to current HEAD
	git -C "${repo_path}" update-ref "${backup_ref}" "${head_hash}"

	# Also update a "last" pointer that includes the operation name
	# Format: refs/git-hex/last/<timestamp>_<operation>
	# First, delete any existing "last" refs
	local existing_last
	existing_last="$(git -C "${repo_path}" for-each-ref --format='%(refname)' "${GIT_HEX_REF_PREFIX}/last/" 2>/dev/null || echo "")"
	if [ -n "${existing_last}" ]; then
		echo "${existing_last}" | while read -r ref; do
			git -C "${repo_path}" update-ref -d "${ref}" 2>/dev/null || true
		done
	fi

	# Create the new "last" ref with operation in the name
	git -C "${repo_path}" update-ref "${GIT_HEX_REF_PREFIX}/last/${timestamp}_${operation}" "${head_hash}"

	# Return the ref name (without refs/ prefix for display)
	echo "git-hex/backup/${timestamp}_${operation}"
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

	# Extract operation name and timestamp from ref name
	# Format: refs/git-hex/last/<timestamp>_<operation>
	local ref_basename
	ref_basename="${last_ref##*/}" # Get just the "timestamp_operation" part

	local timestamp=""
	local operation=""
	# Parse timestamp_operation format using parameter expansion (more portable than regex)
	if [[ "${ref_basename}" == *_* ]]; then
		timestamp="${ref_basename%%_*}" # Everything before first underscore
		operation="${ref_basename#*_}" # Everything after first underscore
	fi

	# Find the corresponding backup ref
	local backup_ref=""
	backup_ref="$(git -C "${repo_path}" for-each-ref --sort=-creatordate --format='%(refname:short)' "${GIT_HEX_REF_PREFIX}/backup/" 2>/dev/null | head -1 || echo "")"

	echo "${backup_hash}|${operation}|${timestamp}|${backup_ref}"
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

	if [ -n "${refs_to_delete}" ]; then
		echo "${refs_to_delete}" | while read -r ref; do
			git -C "${repo_path}" update-ref -d "${ref}" 2>/dev/null || true
		done
	fi
}
