#!/usr/bin/env bash
set -euo pipefail

# Manual registry hooks for git-hex.
#
# Note: mcp-bash-framework v0.7.0+ runs project hooks only when
# MCPBASH_ALLOW_PROJECT_HOOKS=true and this file has safe ownership/permissions.
# Keep this hook minimal and deterministic.

mcp_completion_manual_begin
mcp_completion_register_manual '{"name":"git-hex-ref","path":"completions/git-ref.sh","timeoutSecs":2}'
mcp_completion_register_manual '{"name":"git-hex-commit","path":"completions/commit-sha.sh","timeoutSecs":2}'
mcp_completion_register_manual '{"name":"git-hex-conflict-path","path":"completions/conflict-path.sh","timeoutSecs":2}'
mcp_completion_manual_finalize
