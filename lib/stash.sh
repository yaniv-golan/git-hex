#!/usr/bin/env bash
# Stash helpers shared by git-hex tools
# NOTE: Tools are expected to validate repo existence and HEAD before calling.

set -euo pipefail

_git_hex_stash_message() {
	date +%s
}

_git_hex_random_hex() {
	if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
		LC_ALL=C od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
		return 0
	fi
	printf '%s' "${RANDOM:-0}${RANDOM:-0}${RANDOM:-0}"
}

_git_hex_stash_unique_token() {
	printf '%s-%s-%s-%s' "$(_git_hex_stash_message)" "$$" "${RANDOM:-0}" "$(_git_hex_random_hex)"
}

# Determine whether the repo has uncommitted changes that should be stashed.
# Mode "keep-index" still stashes tracked staged/unstaged changes (but preserves the index).
git_hex_should_stash() {
	local repo_path="$1"
	local mode="${2:-normal}"

	# We intentionally ignore untracked files for safety; tools generally only
	# require that tracked changes are clean unless explicitly documented.
	if ! git -C "${repo_path}" diff --quiet -- 2>/dev/null || ! git -C "${repo_path}" diff --cached --quiet -- 2>/dev/null; then
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
		message="git-hex auto-stash $(_git_hex_stash_unique_token)"
		if [ "${mode}" = "keep-index" ]; then
			# Preserve staged changes while capturing an immutable stash object ID
			stash_push_err=""
			if ! stash_push_err="$(git -C "${repo_path}" stash push --keep-index -m "${message}" 2>&1)"; then
				if [ -n "${stash_push_err}" ] && command -v mcp_log_warn >/dev/null 2>&1; then
					mcp_log_warn "git-hex" "$(printf '{"message":"Auto-stash failed (keep-index): %s"}' "${stash_push_err%%$'\n'*}")"
				fi
			fi
		else
			stash_push_err=""
			if ! stash_push_err="$(git -C "${repo_path}" stash push -m "${message}" 2>&1)"; then
				if [ -n "${stash_push_err}" ] && command -v mcp_log_warn >/dev/null 2>&1; then
					mcp_log_warn "git-hex" "$(printf '{"message":"Auto-stash failed: %s"}' "${stash_push_err%%$'\n'*}")"
				fi
			fi
		fi

		# Record the specific stash ref so we restore exactly what we created, even under concurrency.
		local stash_oid stash_name
		stash_oid=""
		stash_name=""
		while IFS=$'\x1f' read -r oid name subj; do
			[ -n "${oid}" ] || continue
			[ -n "${name}" ] || continue
			# Stash subjects typically look like "On <branch>: <message>".
			if [ -n "${subj}" ] && [[ "${subj}" == *": ${message}" ]]; then
				stash_oid="${oid}"
				stash_name="${name}"
				break
			fi
		done < <(git -C "${repo_path}" stash list --pretty='%H%x1f%gd%x1f%gs' 2>/dev/null || true)

		if [ -n "${stash_oid}" ]; then
			echo "stash:${mode}:${stash_oid}|${stash_name}"
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
				patch_file="$(mktemp "${TMPDIR:-/tmp}/git-hex.stash.patch.XXXXXX")"
				local tmp_index index_path
				tmp_index="$(mktemp "${TMPDIR:-/tmp}/git-hex.stash.index.XXXXXX")"
				index_path="$(git -C "${repo_path}" rev-parse --git-path index 2>/dev/null || true)"
				if [ -n "${index_path}" ]; then
					case "${index_path}" in
					/*) ;;
					*) index_path="${repo_path}/${index_path}" ;;
					esac
				fi
				if [ -n "${index_path}" ] && [ -f "${index_path}" ]; then
					cp -f "${index_path}" "${tmp_index}" 2>/dev/null || true
				fi
				# Apply only the unstaged portion (worktree minus index) to avoid reapplying staged changes.
				# Stash commit structure:
				# - stash@{0} tree: worktree state at time of stashing
				# - ^1: base commit (HEAD at time of stashing)
				# - ^2: index state commit (staged changes)
				# - ^3: untracked state commit (only when using --include-untracked / -u)
				local index_parent=""
				if git -C "${repo_path}" rev-parse "${stash_ref}^2^{tree}" >/dev/null 2>&1; then
					index_parent="${stash_ref}^2"
				elif git -C "${repo_path}" rev-parse "${stash_ref}^1^{tree}" >/dev/null 2>&1; then
					index_parent="${stash_ref}^1"
				fi

				if [ -n "${index_parent}" ] && git -C "${repo_path}" diff "${index_parent}" "${stash_ref}" --binary >"${patch_file}" 2>/dev/null; then
					if [ -s "${patch_file}" ]; then
						if GIT_INDEX_FILE="${tmp_index}" git -C "${repo_path}" apply --3way "${patch_file}" >/dev/null 2>&1; then
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
				rm -f "${tmp_index}" 2>/dev/null || true

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
