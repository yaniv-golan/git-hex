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
		local message
		message="git-hex auto-stash $(_git_hex_stash_message)"
		if [ "${mode}" = "keep-index" ]; then
			# Preserve staged changes while capturing a stash entry reference
			git -C "${repo_path}" stash push --keep-index -m "${message}" >/dev/null 2>&1 || true
			echo "stash:stash@{0}"
		else
			git -C "${repo_path}" stash push -m "${message}" >/dev/null 2>&1 || true
			echo "true"
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
		local stash_ref="${stash_created#stash:}"
		if git -C "${repo_path}" rev-parse --verify "${stash_ref}" >/dev/null 2>&1; then
			local patch_file
			patch_file="$(mktemp)"
			# Apply only the unstaged portion (worktree minus index) to avoid reapplying staged changes
			if git -C "${repo_path}" diff "${stash_ref}^2" "${stash_ref}" --binary >"${patch_file}" 2>/dev/null; then
				if [ -s "${patch_file}" ]; then
					if git -C "${repo_path}" apply --3way "${patch_file}" >/dev/null 2>&1; then
						git -C "${repo_path}" stash drop "${stash_ref}" >/dev/null 2>&1 || true
					else
						stash_not_restored="true"
						if command -v mcp_log >/dev/null 2>&1; then
							local log_payload
							log_payload="$(printf '{"message":"Auto-stash could not be restored cleanly. Run git stash pop %s manually."}' "${stash_ref}")"
							mcp_log "warn" "git-hex" "${log_payload}"
						fi
					fi
				else
					git -C "${repo_path}" stash drop "${stash_ref}" >/dev/null 2>&1 || true
				fi
			else
				stash_not_restored="true"
			fi
			rm -f "${patch_file}" 2>/dev/null || true
		fi
		echo "${stash_not_restored}"
		return 0
	fi

	if [ "${stash_created}" = "true" ]; then
		if ! git -C "${repo_path}" stash pop >/dev/null 2>&1; then
			stash_not_restored="true"
			if command -v mcp_log >/dev/null 2>&1; then
				local log_payload='{"message":"Auto-stash could not be restored cleanly. Run git stash pop manually."}'
				mcp_log "warn" "git-hex" "${log_payload}"
			fi
		fi
	fi

	echo "${stash_not_restored}"
}
