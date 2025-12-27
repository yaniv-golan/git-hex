#!/usr/bin/env bash
# server.d/health-checks.sh - verify external dependencies for git-hex
#
# This hook runs when `mcp-bash health` is called and verifies that all
# required external dependencies are available before the server starts
# serving requests.

# Required: git command-line tool
mcp_health_check_command "git" "Git version control (required for all operations)"

# Note: jq/gojq detection is handled by mcp-bash framework via MCPBASH_JSON_TOOL_BIN.
# If JSON tooling is missing, mcp-bash enters minimal mode automatically.

# Recommended: git version check
git_version=$(git --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ -n "${git_version}" ]]; then
	# Parse major.minor
	IFS='.' read -r major minor _patch <<<"${git_version}"
	if ((major < 2 || (major == 2 && minor < 20))); then
		mcp_log_warn "git-hex" "Git ${git_version} found; 2.20+ required, 2.33+ recommended for ort merge strategy"
	fi
fi
