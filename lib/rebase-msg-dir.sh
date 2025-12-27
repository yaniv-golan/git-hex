#!/usr/bin/env bash
# Cleanup helper for rebaseWithPlan temporary message directories.
#
# These directories must persist while a rebase is paused because the rebase todo
# can contain `exec git commit ... -F <path>` lines that reference files inside
# the directory. The directory path is recorded in a marker file under `.git/`.

set -euo pipefail

_git_hex_cleanup_rebase_msg_dir() {
	local marker_file="$1"
	[ -f "${marker_file}" ] || return 0

	local msg_dir=""
	msg_dir="$(head -1 "${marker_file}" 2>/dev/null | tr -d '\r\n')"
	rm -f -- "${marker_file}" 2>/dev/null || true

	[ -n "${msg_dir}" ] || return 0
	case "${msg_dir}" in
	/*) ;;
	*) return 0 ;;
	esac

	local msg_base="${msg_dir##*/}"
	case "${msg_base}" in
	githex.rebase.msg.*) ;;
	*) return 0 ;;
	esac

	[ -d "${msg_dir}" ] || return 0
	rm -rf -- "${msg_dir}" 2>/dev/null || true
	return 0
}
