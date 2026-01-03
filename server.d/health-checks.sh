#!/usr/bin/env bash
# server.d/health-checks.sh - verify external dependencies for git-hex
#
# This hook runs when `mcp-bash health` is called and verifies that all
# required external dependencies are available before the server starts
# serving requests.

# Required: git command-line tool
mcp_health_check_command "git" "Git version control (required for all operations)"

# Optional but recommended: jq for JSON processing (framework handles fallback)
# mcp_health_check_command "jq" "JSON processor (optional, gojq also works)"
