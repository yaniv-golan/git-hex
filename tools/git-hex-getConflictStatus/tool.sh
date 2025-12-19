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

git_dir="$(git_hex_get_git_dir "${repo_path}")"
rebase_merge_dir="${git_dir}/rebase-merge"
rebase_apply_dir="${git_dir}/rebase-apply"
cherry_pick_head_path="${git_dir}/CHERRY_PICK_HEAD"
merge_head_path="${git_dir}/MERGE_HEAD"
rebase_head_path="${git_dir}/REBASE_HEAD"

if [ -n "${rebase_merge_dir}" ] && [ -d "${rebase_merge_dir}" ]; then
	conflict_type="rebase"
	if [ -f "${rebase_merge_dir}/msgnum" ]; then
		current_step="$(cat "${rebase_merge_dir}/msgnum")"
	fi
	if [ -f "${rebase_merge_dir}/end" ]; then
		total_steps="$(cat "${rebase_merge_dir}/end")"
	fi
	if [ -f "${rebase_merge_dir}/stopped-sha" ]; then
		conflicting_commit="$(cat "${rebase_merge_dir}/stopped-sha")"
	fi
elif [ -n "${rebase_apply_dir}" ] && [ -d "${rebase_apply_dir}" ]; then
	conflict_type="rebase"
	if [ -f "${rebase_apply_dir}/next" ]; then
		current_step="$(cat "${rebase_apply_dir}/next")"
	fi
	if [ -f "${rebase_apply_dir}/last" ]; then
		total_steps="$(cat "${rebase_apply_dir}/last")"
	fi
elif [ -n "${cherry_pick_head_path}" ] && [ -f "${cherry_pick_head_path}" ]; then
	conflict_type="cherry-pick"
	conflicting_commit="$(cat "${cherry_pick_head_path}")"
elif [ -n "${merge_head_path}" ] && [ -f "${merge_head_path}" ]; then
	conflict_type="merge"
	conflicting_commit="$(cat "${merge_head_path}")"
else
	mcp_emit_json '{"success": true, "inConflict": false, "conflictType": "none", "summary": "No conflicts detected"}'
	exit 0
fi

if [ -z "${conflicting_commit}" ] && [ -f "${rebase_head_path}" ]; then
	conflicting_commit="$(cat "${rebase_head_path}" 2>/dev/null || true)"
fi

conflicting_files="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"

if [ -z "${conflicting_files}" ]; then
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

files_json="[]"
while  IFS= read -r file; do
	[ -z "${file}" ] && continue
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
		if [ -f "${repo_path}/${file}" ]; then
			# Treat empty files as text (grep -I can misclassify empties).
			if [ -s "${repo_path}/${file}" ] && ! grep -Iq . "${repo_path}/${file}" 2>/dev/null; then
				is_binary="true"
			fi
		else
			# Prefer checking the stage-2 blob (ours). Treat empty blob as text.
			ours_size_for_binary="$(git -C "${repo_path}" cat-file -s ":2:${file}" 2>/dev/null || echo "0")"
			if [ "${ours_size_for_binary}" -gt 0 ] && ! git -C "${repo_path}" cat-file -p ":2:${file}" 2>/dev/null | grep -Iq .; then
				is_binary="true"
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
			working_size="$(LC_ALL=C wc -c <"${repo_path}/${file}" 2>/dev/null | tr -d ' ' || echo "0")"
			truncated="false"
			if [ "${base_size}" -gt "${max_content}" ] || [ "${ours_size}" -gt "${max_content}" ] || [ "${theirs_size}" -gt "${max_content}" ] || [ "${working_size}" -gt "${max_content}" ]; then
				truncated="true"
			fi

			base_content="$(git -C "${repo_path}" show ":1:${file}" 2>/dev/null | head -c "${max_content}" || echo "")"
			ours_content="$(git -C "${repo_path}" show ":2:${file}" 2>/dev/null | head -c "${max_content}" || echo "")"
			theirs_content="$(git -C "${repo_path}" show ":3:${file}" 2>/dev/null | head -c "${max_content}" || echo "")"
			working_content="$(head -c "${max_content}" "${repo_path}/${file}" 2>/dev/null || echo "")"

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
done <<<"${conflicting_files}"

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
