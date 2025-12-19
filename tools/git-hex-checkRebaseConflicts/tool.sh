#!/usr/bin/env bash
set -euo pipefail

# Enable shell tracing for debugging (shows every command executed)
if [ "${GIT_HEX_DEBUG:-}" = "true" ]; then
	set -x
fi

# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
onto="$(mcp_args_require '.onto')"
max_commits="$(mcp_args_int '.maxCommits' --default 100 --min 1)"

# Validate repo
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

# Check git version (require 2.38+)
git_version_raw="$(git --version | sed 's/git version //')"
git_major="$(echo "${git_version_raw}" | cut -d. -f1)"
git_minor="$(echo "${git_version_raw}" | cut -d. -f2)"
git_major="${git_major%%[^0-9]*}"
git_minor="${git_minor%%[^0-9]*}"
git_minor="${git_minor:-0}"
if [ "${git_major}" -lt 2 ] || { [ "${git_major}" -eq 2 ] && [ "${git_minor}" -lt 38 ]; }; then
	mcp_fail_invalid_args "checkRebaseConflicts requires Git 2.38+ for merge-tree support. Current version: ${git_version_raw}"
fi

# Validate onto
if ! git -C "${repo_path}" rev-parse "${onto}" >/dev/null 2>&1; then
	mcp_fail_invalid_args "Invalid onto ref: ${onto}"
fi

object_dir="$(mktemp -d "${TMPDIR:-/tmp}/githex.objects.XXXXXX")"
alt_objects="$(git -C "${repo_path}" rev-parse --git-path objects 2>/dev/null || true)"
cleanup() {
	rm -rf "${object_dir}" 2>/dev/null || true
}
trap cleanup EXIT

# Use a temporary object directory so merge-tree does not write objects into the repo
export GIT_OBJECT_DIRECTORY="${object_dir}"
export GIT_ALTERNATE_OBJECT_DIRECTORIES="${alt_objects}"

total_commits="$(git -C "${repo_path}" rev-list --count "${onto}..HEAD" 2>/dev/null || echo "0")"
current_tree="$(git -C "${repo_path}" rev-parse "${onto}^{tree}")"

would_conflict="false"
first_conflict_index=""
first_conflict_hash=""
commits_json="[]"
commit_index=0
limit_exceeded="false"

log_format='%H%x1f%P%x1f%s'
commit_stream="$(git -C "${repo_path}" log --reverse --format="${log_format}" "${onto}..HEAD")"
if [ "${total_commits}" -gt "${max_commits}" ]; then
	limit_exceeded="true"
	commit_stream="$(printf '%s\n' "${commit_stream}" | head -n "${max_commits}")"
fi

while IFS=$'\x1f' read -r commit parents subject; do
	[ -z "${commit}" ] && continue
	commit_index=$((commit_index + 1))

	if [ "${would_conflict}" = "true" ]; then
		# shellcheck disable=SC2016
		commit_json="$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--arg hash "${commit}" \
			--arg subject "${subject}" \
			'{hash: $hash, subject: $subject, prediction: "unknown"}')"
		# shellcheck disable=SC2016
		commits_json="$(printf '%s' "${commits_json}" | "${MCPBASH_JSON_TOOL_BIN}" --argjson c "${commit_json}" '. + [$c]')"
		continue
	fi

	parent="${parents%% *}"
	if [ -z "${parent}" ]; then
		parent="$(git -C "${repo_path}" hash-object -t tree /dev/null)"
	fi

	result="$(git -C "${repo_path}" merge-tree --write-tree --merge-base="${parent}" "${current_tree}" "${commit}" 2>&1 || true)"
	tree_sha="$(echo "${result}" | head -1)"
	has_conflict=""
	if echo "${result}" | grep -qi "CONFLICT"; then
		has_conflict="true"
	fi
	if [ -z "${has_conflict}" ] && [ -n "${tree_sha}" ]; then
		conflict_found=""
		while IFS=$'\t' read -r meta _path; do
			[ -z "${meta}" ] && continue
			sha="${meta##* }"
			if git -C "${repo_path}" cat-file blob "${sha}" 2>/dev/null | grep -q "^<<<<<<< "; then
				conflict_found="true"
				break
			fi
		done < <(git -C "${repo_path}" ls-tree -r "${tree_sha}" 2>/dev/null)
		[ "${conflict_found}" = "true" ] && has_conflict="true"
	fi

	if [ "${has_conflict}" = "true" ]; then
		would_conflict="true"
		if [ -z "${first_conflict_index}" ]; then
			first_conflict_index="${commit_index}"
			first_conflict_hash="${commit}"
		fi
		# shellcheck disable=SC2016
		commit_json="$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--arg hash "${commit}" \
			--arg subject "${subject}" \
			'{hash: $hash, subject: $subject, prediction: "conflict"}')"
	else
		# shellcheck disable=SC2016
		commit_json="$("${MCPBASH_JSON_TOOL_BIN}" -n \
			--arg hash "${commit}" \
			--arg subject "${subject}" \
			'{hash: $hash, subject: $subject, prediction: "clean"}')"
		current_tree="${tree_sha}"
	fi
	# shellcheck disable=SC2016
	commits_json="$(printf '%s' "${commits_json}" | "${MCPBASH_JSON_TOOL_BIN}" --argjson c "${commit_json}" '. + [$c]')"
done <<<"${commit_stream}"

if [ "${would_conflict}" = "true" ]; then
	summary="Rebase would conflict at commit ${first_conflict_index}/${total_commits} (${first_conflict_hash:0:7})"
elif [ "${limit_exceeded}" = "true" ]; then
	summary="Checked first ${max_commits} of ${total_commits} commits - no conflicts found in checked range"
else
	summary="Rebase predicted to complete cleanly"
fi

# shellcheck disable=SC2016
mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson wouldConflict "${would_conflict}" \
	--argjson commits "${commits_json}" \
	--argjson limitExceeded "${limit_exceeded}" \
	--argjson totalCommits "${total_commits}" \
	--argjson checkedCommits "${commit_index}" \
	--arg summary "${summary}" \
	'{
		success: true,
		wouldConflict: $wouldConflict,
		confidence: "estimate",
		commits: $commits,
		limitExceeded: $limitExceeded,
		totalCommits: $totalCommits,
		checkedCommits: $checkedCommits,
		summary: $summary,
		note: "Predictions may not match actual rebase behavior in all cases"
	}')"
