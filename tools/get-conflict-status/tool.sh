#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
include_content="$(mcp_args_bool '.includeContent' --default false)"
max_content="$(mcp_args_int '.maxContentSize' --default 10000 --min 0)"

# Validate git repository
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
	mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

conflict_type=""
current_step=0
total_steps=0
conflicting_commit=""

if [ -d "${repo_path}/.git/rebase-merge" ]; then
	conflict_type="rebase"
	if [ -f "${repo_path}/.git/rebase-merge/msgnum" ]; then
		current_step="$(cat "${repo_path}/.git/rebase-merge/msgnum")"
	fi
	if [ -f "${repo_path}/.git/rebase-merge/end" ]; then
		total_steps="$(cat "${repo_path}/.git/rebase-merge/end")"
	fi
	if [ -f "${repo_path}/.git/rebase-merge/stopped-sha" ]; then
		conflicting_commit="$(cat "${repo_path}/.git/rebase-merge/stopped-sha")"
	fi
elif [ -d "${repo_path}/.git/rebase-apply" ]; then
	conflict_type="rebase"
	if [ -f "${repo_path}/.git/rebase-apply/next" ]; then
		current_step="$(cat "${repo_path}/.git/rebase-apply/next")"
	fi
	if [ -f "${repo_path}/.git/rebase-apply/last" ]; then
		total_steps="$(cat "${repo_path}/.git/rebase-apply/last")"
	fi
elif [ -f "${repo_path}/.git/CHERRY_PICK_HEAD" ]; then
	conflict_type="cherry-pick"
	conflicting_commit="$(cat "${repo_path}/.git/CHERRY_PICK_HEAD")"
elif [ -f "${repo_path}/.git/MERGE_HEAD" ]; then
	conflict_type="merge"
	conflicting_commit="$(cat "${repo_path}/.git/MERGE_HEAD")"
else
	mcp_emit_json '{"success": true, "inConflict": false, "summary": "No conflicts detected"}'
	exit 0
fi

conflicting_files="$(git -C "${repo_path}" diff --name-only --diff-filter=U 2>/dev/null || true)"

if [ -z "${conflicting_files}" ]; then
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
while IFS= read -r file; do
	[ -z "${file}" ] && continue
	stages="$(git -C "${repo_path}" ls-files -u -- "${file}" 2>/dev/null | awk '{print $3}' | sort -u | tr '\n' ',')"
	case "${stages}" in
	"1,2,3,") file_conflict_type="both_modified" ;;
	"1,3,") file_conflict_type="deleted_by_us" ;;
	"1,2,") file_conflict_type="deleted_by_them" ;;
	"2,3,") file_conflict_type="added_by_both" ;;
	*) file_conflict_type="unknown" ;;
	esac

	if [ "${include_content}" = "true" ]; then
		is_binary=""
		if [ -f "${repo_path}/${file}" ]; then
			if [ ! -s "${repo_path}/${file}" ]; then
				is_binary=""
			elif grep -Iq . "${repo_path}/${file}" 2>/dev/null; then
				is_binary=""
			else
				if grep -q '[^[:space:]]' "${repo_path}/${file}" 2>/dev/null; then
					is_binary="true"
				else
					is_binary=""
				fi
			fi
		else
			is_binary=""
		fi

		if [ "${is_binary}" = "true" ]; then
			files_json="$(echo "${files_json}" | "${MCPBASH_JSON_TOOL_BIN}" \
				--arg path "${file}" \
				--arg type "${file_conflict_type}" \
				--argjson isBinary true \
				'. + [{path: $path, conflictType: $type, isBinary: $isBinary, note: "Binary file - content not included"}]')"
		else
			base_content="$(git -C "${repo_path}" show ":1:${file}" 2>/dev/null | head -c "${max_content}" || echo "")"
			ours_content="$(git -C "${repo_path}" show ":2:${file}" 2>/dev/null | head -c "${max_content}" || echo "")"
			theirs_content="$(git -C "${repo_path}" show ":3:${file}" 2>/dev/null | head -c "${max_content}" || echo "")"
			working_content="$(head -c "${max_content}" "${repo_path}/${file}" 2>/dev/null || echo "")"

			files_json="$(echo "${files_json}" | "${MCPBASH_JSON_TOOL_BIN}" \
				--arg path "${file}" \
				--arg type "${file_conflict_type}" \
				--argjson isBinary false \
				--arg base "${base_content}" \
				--arg ours "${ours_content}" \
				--arg theirs "${theirs_content}" \
				--arg working "${working_content}" \
				'. + [{path: $path, conflictType: $type, isBinary: $isBinary, base: $base, ours: $ours, theirs: $theirs, workingCopy: $working}]')"
		fi
	else
		files_json="$(echo "${files_json}" | "${MCPBASH_JSON_TOOL_BIN}" \
			--arg path "${file}" \
			--arg type "${file_conflict_type}" \
			'. + [{path: $path, conflictType: $type}]')"
	fi
done <<<"${conflicting_files}"

file_count="$(echo "${files_json}" | "${MCPBASH_JSON_TOOL_BIN}" 'length')"

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
