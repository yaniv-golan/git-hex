#!/usr/bin/env bash
# Stash helpers shared by git-hex tools
# NOTE: Tools are expected to validate repo existence and HEAD before calling.

set -euo pipefail

_git_hex_stash_message() {
	date +%s
}

# Determine whether the repo has uncommitted changes that should be stashed.
# Mode "keep-index" still stashes tracked staged/unstaged changes (but preserves the index).
git_hex_should_stash() {
	local repo_path="$1"
	local mode="${2:-normal}"

	if ! git -C "${repo_path}" diff-index --quiet HEAD -- 2>/dev/null; then
		echo "true"
		return 0
	fi
	echo "false"
}

# Create a stash when the repo is dirty. Echoes "true" if a stash was created.
git_hex_auto_stash() {
	local repo_path="$1"
	local mode="${2:-normal}"

	local should_stash
	should_stash="$(git_hex_should_stash "${repo_path}" "${mode}")"
	if [ "${should_stash}" = "true" ]; then
		# Track top-of-stack before creating a new stash so we don't operate on a pre-existing one
		local before_top
		before_top="$(git -C "${repo_path}" stash list --pretty='%H' -n 1 2>/dev/null || echo "")"

		local message
		message="git-hex auto-stash $(_git_hex_stash_message)"
		if [ "${mode}" = "keep-index" ]; then
			# Preserve staged changes while capturing an immutable stash object ID
			git -C "${repo_path}" stash push --keep-index -m "${message}" >/dev/null 2>&1 || true
		else
			git -C "${repo_path}" stash push -m "${message}" >/dev/null 2>&1 || true
		fi

		# Record the specific stash ref so we restore exactly what we created
		local stash_oid stash_name
		stash_oid="$(git -C "${repo_path}" rev-parse 'stash@{0}' 2>/dev/null || true)"
		stash_name="$(git -C "${repo_path}" stash list --pretty='%gd' -n 1 2>/dev/null || true)"
		if [ -n "${stash_oid}" ] && [ "${stash_oid}" != "${before_top}" ]; then
			echo "stash:${mode}:${stash_oid}|${stash_name:-stash@{0}}"
		else
			echo "false"
		fi
	else
		echo "false"
	fi
}

# Restore a previously created stash. Echoes "true" if stash could not be restored.
git_hex_restore_stash() {
	local repo_path="$1"
	local stash_created="${2:-false}"
	local stash_not_restored="false"

	if [[ "${stash_created}" == stash:* ]]; then
		local payload="${stash_created#stash:}"
		local mode_hint="normal"
		# New format: <mode>:<oid>|<name>; fallback to old format if no mode prefix
		if [[ "${payload}" == *:* ]]; then
			mode_hint="${payload%%:*}"
			payload="${payload#*:}"
			if [ -z "${payload}" ]; then
				mode_hint="normal"
				payload="${stash_created#stash:}"
			fi
		fi
		local stash_ref
		local stash_name=""
		if [[ "${payload}" == *"|"* ]]; then
			stash_ref="${payload%%|*}"
			stash_name="${payload#*|}"
		else
			stash_ref="${payload}"
		fi
		if git -C "${repo_path}" rev-parse --verify "${stash_ref}" >/dev/null 2>&1; then
			if [ -z "${stash_name}" ]; then
				stash_name="$(git -C "${repo_path}" stash list --pretty='%H %gd' 2>/dev/null | awk -v oid="${stash_ref}" '$1==oid{print $2; exit}')"
			fi
			if [ "${mode_hint}" = "keep-index" ]; then
				local patch_file
				patch_file="$(mktemp)"
				# Apply only the unstaged portion (worktree minus index) to avoid reapplying staged changes.
				# Stash commits have three parents: base (^1), index (^2), worktree (^3). For older formats or
				# keep-index with fewer parents, fall back to ^2.
				local worktree_parent=""
				if git -C "${repo_path}" rev-parse "${stash_ref}^3^{tree}" >/dev/null 2>&1; then
					worktree_parent="${stash_ref}^3"
				elif git -C "${repo_path}" rev-parse "${stash_ref}^2^{tree}" >/dev/null 2>&1; then
					worktree_parent="${stash_ref}^2"
				fi

				if [ -n "${worktree_parent}" ] && git -C "${repo_path}" diff "${worktree_parent}" "${stash_ref}" --binary >"${patch_file}" 2>/dev/null; then
					if [ -s "${patch_file}" ]; then
						if git -C "${repo_path}" apply --3way "${patch_file}" >/dev/null 2>&1; then
							git -C "${repo_path}" stash drop "${stash_name:-${stash_ref}}" >/dev/null 2>&1 || true
							stash_not_restored="false"
						else
							stash_not_restored="true"
						fi
					else
						git -C "${repo_path}" stash drop "${stash_name:-${stash_ref}}" >/dev/null 2>&1 || true
					fi
				else
					stash_not_restored="true"
				fi
				rm -f "${patch_file}" 2>/dev/null || true

				if [ "${stash_not_restored}" = "true" ] && command -v mcp_log_warn >/dev/null 2>&1; then
					local log_payload
					log_payload="$(printf '{"message":"Auto-stash could not be restored cleanly. Run git stash pop --index %s manually."}' "${stash_name:-${stash_ref}}")"
					mcp_log_warn "git-hex" "${log_payload}"
				fi
			else
				if ! git -C "${repo_path}" stash pop "${stash_name:-${stash_ref}}" >/dev/null 2>&1; then
					stash_not_restored="true"
					if command -v mcp_log >/dev/null 2>&1; then
						local log_payload
						log_payload="$(printf '{"message":"Auto-stash could not be restored cleanly. Run git stash pop %s manually."}' "${stash_name:-${stash_ref}}")"
						mcp_log "warn" "git-hex" "${log_payload}"
					fi
				fi
			fi
		fi
		echo "${stash_not_restored}"
		return 0
	fi

	echo "${stash_not_restored}"
}
