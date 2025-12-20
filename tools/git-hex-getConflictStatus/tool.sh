#!/usr/bin/env bash
set -euo pipefail

# Enable shell tracing for debugging (shows every command executed)
if [ "${GIT_HEX_DEBUG:-}" = "true" ]; then
	set -x
fi

# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/git-helpers.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/git-helpers.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
include_content="$(mcp_args_bool '.includeContent' --default false)"
max_content="$(mcp_args_int '.maxContentSize' --default 10000 --min 0)"

# Validate git repository
git_hex_require_repo "${repo_path}"

conflict_type=""
current_step=0
total_steps=0
conflicting_commit=""

git_dir="$( git_hex_get_git_dir "${repo_path}")"
rebase_merge_dir="${git_dir}/rebase-merge"
rebase_apply_dir="${git_dir}/rebase-apply"
cherry_pick_head_path="${git_dir}/CHERRY_PICK_HEAD"
revert_head_path="${git_dir}/REVERT_HEAD"
merge_head_path="${git_dir}/MERGE_HEAD"
rebase_head_path="${git_dir}/REBASE_HEAD"

if  [ -n "${rebase_merge_dir}" ] && [ -d "${rebase_merge_dir}" ]; then
	conflict_type="rebase"
	if [ -f "${rebase_merge_dir}/msgnum" ]; then
		current_step="$(<"${rebase_merge_dir}/msgnum")"
	fi
	if [ -f "${rebase_merge_dir}/end" ]; then
		total_steps="$(<"${rebase_merge_dir}/end")"
	fi
	if [ -f "${rebase_merge_dir}/stopped-sha" ]; then
		conflicting_commit="$(<"${rebase_merge_dir}/stopped-sha")"
	fi
elif   [ -n "${rebase_apply_dir}" ] && [ -d "${rebase_apply_dir}" ]; then
	conflict_type="rebase"
	if [ -f "${rebase_apply_dir}/next" ]; then
		current_step="$(<"${rebase_apply_dir}/next")"
	fi
	if [ -f "${rebase_apply_dir}/last" ]; then
		total_steps="$(<"${rebase_apply_dir}/last")"
	fi
	# Prefer original-commit for rebase-apply when available.
	if [ -f "${rebase_apply_dir}/original-commit" ]; then
		conflicting_commit="$(<"${rebase_apply_dir}/original-commit")"
	elif [ -f "${rebase_apply_dir}/patch" ]; then
		# Best-effort fallback: some rebase-apply flows may not have original-commit.
		# If the patch is in mailbox format, it may include a "From <sha> ..." header.
		patch_sha="$(LC_ALL=C awk '$1=="From" && $2 ~ /^[0-9a-f]{40}$/ {print $2; exit}' "${rebase_apply_dir}/patch" 2>/dev/null || true)"
		if [ -n "${patch_sha}" ]; then
			conflicting_commit="$(git -C "${repo_path}" rev-parse --verify "${patch_sha}^{commit}" 2>/dev/null || echo "")"
		fi
	fi
elif    [ -n "${cherry_pick_head_path}" ] && [ -f "${cherry_pick_head_path}" ]; then
	conflict_type="cherry-pick"
	conflicting_commit="$(<"${cherry_pick_head_path}")"
elif    [ -n "${revert_head_path}" ] && [ -f "${revert_head_path}" ]; then
	conflict_type="revert"
	conflicting_commit="$(<"${revert_head_path}")"
elif   [ -n "${merge_head_path}" ] && [ -f "${merge_head_path}" ]; then
	conflict_type="merge"
	conflicting_commit="$(<"${merge_head_path}")"
else
	mcp_emit_json '{"success": true, "inConflict": false, "conflictType": "none", "summary": "No conflicts detected"}'
	exit 0
fi

if  [ -z "${conflicting_commit}" ] && [ -f "${rebase_head_path}" ]; then
	conflicting_commit="$(cat "${rebase_head_path}" 2>/dev/null || true)"
fi

files_json="[]"
have_conflicts="false"
# Use NUL-delimited output to avoid mis-parsing filenames containing newlines.
while  IFS= read -r -d '' file; do
	[ -z "${file}" ] && continue
	have_conflicts="true"

	stages="$(git -C "${repo_path}" ls-files -u -- "${file}" 2>/dev/null | awk '{print $3}' | sort -u | tr '\n' ',')"
	case "${stages}" in
	"1,2,3,") file_conflict_type="both_modified" ;;
	"1,3,") file_conflict_type="deleted_by_us" ;;
	"1,2,") file_conflict_type="deleted_by_them" ;;
	"2,3,") file_conflict_type="added_by_both" ;;
	"1,") file_conflict_type="deleted_by_both" ;;
	*) file_conflict_type="unknown" ;;
	esac

	if [ "${include_content}" = "true" ]; then
		if ! git_hex_is_safe_repo_relative_path "${file}"; then
			# shellcheck disable=SC2016
			files_json="$(printf '%s' "${files_json}" | "${MCPBASH_JSON_TOOL_BIN}" \
				--arg path "${file}" \
				--arg type "${file_conflict_type}" \
				'. + [{path: $path, conflictType: $type, note: "Unsafe path; content omitted"}]')"
			continue
		fi

		is_binary="false"
		if command -v file >/dev/null 2>&1; then
			if [ -f "${repo_path}/${file}" ]; then
				enc="$(file -b --mime-encoding "${repo_path}/${file}" 2>/dev/null || true)"
			else
				# Prefer checking the stage-2 blob (ours). For delete conflicts, stage-2 may not exist; fall back to stage-3.
				stage_for_binary="2"
				case "${stages}" in
				"1,3,") stage_for_binary="3" ;; # deleted_by_us -> check theirs
				"1,2,") stage_for_binary="2" ;; # deleted_by_them -> check ours
				esac
				enc="$(git -C "${repo_path}" cat-file -p ":${stage_for_binary}:${file}" 2>/dev/null | file -b --mime-encoding - 2>/dev/null || true)"
			fi
			case "${enc}" in
			binary | unknown*) is_binary="true" ;;
			esac
		else
			if [ -f "${repo_path}/${file}" ]; then
				# Treat empty files as text (grep -I can misclassify empties).
				if [ -s "${repo_path}/${file}" ] && ! grep -Iq . "${repo_path}/${file}" 2>/dev/null; then
					is_binary="true"
				fi
			else
				stage_for_binary="2"
				case "${stages}" in
				"1,3,") stage_for_binary="3" ;;
				"1,2,") stage_for_binary="2" ;;
				esac
				size_for_binary="$(git -C "${repo_path}" cat-file -s ":${stage_for_binary}:${file}" 2>/dev/null || echo "0")"
				if [ "${size_for_binary}" -gt 0 ] && ! git -C "${repo_path}" cat-file -p ":${stage_for_binary}:${file}" 2>/dev/null | grep -Iq .; then
					is_binary="true"
				fi
			fi
		fi

		if [ "${is_binary}" = "true" ]; then
			# shellcheck disable=SC2016
			files_json="$(printf '%s' "${files_json}" | "${MCPBASH_JSON_TOOL_BIN}" \
				--arg path "${file}" \
				--arg type "${file_conflict_type}" \
				--argjson isBinary true \
				'. + [{path: $path, conflictType: $type, isBinary: $isBinary, truncated: false, note: "Binary file - content not included"}]')"
		else
			base_size="$(git -C "${repo_path}" cat-file -s ":1:${file}" 2>/dev/null || echo "0")"
			ours_size="$(git -C "${repo_path}" cat-file -s ":2:${file}" 2>/dev/null || echo "0")"
			theirs_size="$(git -C "${repo_path}" cat-file -s ":3:${file}" 2>/dev/null || echo "0")"
			working_size="0"
			if [ -f "${repo_path}/${file}" ]; then
				working_size="$(LC_ALL=C wc -c <"${repo_path}/${file}" 2>/dev/null | tr -d ' ' || echo "0")"
			fi
			truncated="false"
			if [ "${base_size}" -gt "${max_content}" ] || [ "${ours_size}" -gt "${max_content}" ] || [ "${theirs_size}" -gt "${max_content}" ] || [ "${working_size}" -gt "${max_content}" ]; then
				truncated="true"
			fi

			base_content="$(git -C "${repo_path}" show ":1:${file}" 2>/dev/null | head -c "${max_content}" || echo "")"
			ours_content="$(git -C "${repo_path}" show ":2:${file}" 2>/dev/null | head -c "${max_content}" || echo "")"
			theirs_content="$(git -C "${repo_path}" show ":3:${file}" 2>/dev/null | head -c "${max_content}" || echo "")"
			working_content=""
			if [ -f "${repo_path}/${file}" ]; then
				working_content="$(head -c "${max_content}" "${repo_path}/${file}" 2>/dev/null || echo "")"
			fi

			# shellcheck disable=SC2016
			files_json="$(printf '%s' "${files_json}" | "${MCPBASH_JSON_TOOL_BIN}" \
				--arg path "${file}" \
				--arg type "${file_conflict_type}" \
				--argjson isBinary false \
				--argjson truncated "${truncated}" \
				--arg base "${base_content}" \
				--arg ours "${ours_content}" \
				--arg theirs "${theirs_content}" \
				--arg working "${working_content}" \
				'. + [{path: $path, conflictType: $type, isBinary: $isBinary, truncated: $truncated, base: $base, ours: $ours, theirs: $theirs, workingCopy: $working}]')"
		fi
	else
		# shellcheck disable=SC2016
		files_json="$(printf '%s' "${files_json}" | "${MCPBASH_JSON_TOOL_BIN}" \
			--arg path "${file}" \
			--arg type "${file_conflict_type}" \
			'. + [{path: $path, conflictType: $type}]')"
	fi
done  < <(git -C "${repo_path}" diff --name-only --diff-filter=U -z 2>/dev/null || true)

if  [ "${have_conflicts}" != "true" ]; then
	# shellcheck disable=SC2016
	mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
		--argjson success true \
		--argjson inConflict true \
		--arg conflictType "${conflict_type}" \
		--argjson currentStep "${current_step}" \
		--argjson totalSteps "${total_steps}" \
		--arg conflictingCommit "${conflicting_commit}" \
		--argjson conflictingFiles "[]" \
		--arg summary "${conflict_type} paused - all conflicts resolved, ready to continue" \
		'{success: $success, inConflict: $inConflict, conflictType: $conflictType, currentStep: $currentStep, totalSteps: $totalSteps, conflictingCommit: $conflictingCommit, conflictingFiles: $conflictingFiles, summary: $summary}')"
	exit 0
fi

file_count="$(printf '%s' "${files_json}" | "${MCPBASH_JSON_TOOL_BIN}" 'length')"

# shellcheck disable=SC2016
mcp_emit_json "$("${MCPBASH_JSON_TOOL_BIN}" -n \
	--argjson success true \
	--argjson inConflict true \
	--arg conflictType "${conflict_type}" \
	--argjson currentStep "${current_step}" \
	--argjson totalSteps "${total_steps}" \
	--arg conflictingCommit "${conflicting_commit}" \
	--argjson conflictingFiles "${files_json}" \
	--arg summary "${conflict_type} paused with ${file_count} conflicting file(s)" \
	'{success: $success, inConflict: $inConflict, conflictType: $conflictType, currentStep: $currentStep, totalSteps: $totalSteps, conflictingCommit: $conflictingCommit, conflictingFiles: $conflictingFiles, summary: $summary}')"
