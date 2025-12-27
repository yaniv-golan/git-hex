#!/usr/bin/env bash
# server.d/env.sh - Environment setup for git-hex MCP Server
#
# ==============================================================================
# Tool Environment Passthrough
# ==============================================================================
# Allow policy environment variables to be passed through to tool scripts.
# By default, mcp-bash only passes MCP*/MCPBASH* variables for security.
# We use "allowlist" mode to also pass GIT_HEX_* policy variables.
#
# Available policy variables:
#   GIT_HEX_READ_ONLY=1  - Restrict to read-only operations (getRebasePlan, checkRebaseConflicts, getConflictStatus)

export MCPBASH_TOOL_ENV_MODE="allowlist"
export MCPBASH_TOOL_ENV_ALLOWLIST="GIT_HEX_READ_ONLY,GIT_HEX_DEBUG"

# ==============================================================================
# Debug Mode Configuration
# ==============================================================================
# Enable debug logging by creating server.d/.debug file (mcp-bash 0.9.5+ native):
#
#   touch server.d/.debug   # Enable debug logging
#   rm server.d/.debug      # Disable debug logging
#
# Or via environment variables:
#   MCPBASH_LOG_LEVEL=debug     # Enable mcp-bash framework debug logging
#   GIT_HEX_DEBUG=1             # Enable git-hex-specific debug logging
#   MCPBASH_LOG_VERBOSE=true    # Show paths in logs (security warning: exposes paths)
#   MCPBASH_TRACE_TOOLS=true    # Enable shell tracing (set -x) for tools
#
# Example: Test a single tool with debug logging:
#   MCPBASH_LOG_LEVEL=debug mcp-bash run-tool git-hex-getRebasePlan --args '{"repoPath":"/path/to/repo"}' --verbose
#
# See mcp-bash docs/DEBUGGING.md for details.
# ==============================================================================

# ==============================================================================
# Debug Mode Auto-Configuration
# ==============================================================================
# When MCPBASH_LOG_LEVEL=debug (set by .debug file or env), enable related features

if [[ "${MCPBASH_LOG_LEVEL:-info}" == "debug" ]]; then
	# Enable git-hex-specific debug logging
	export GIT_HEX_DEBUG="${GIT_HEX_DEBUG:-1}"

	# Capture tool stderr for debugging (mcp-bash feature)
	export MCPBASH_TOOL_STDERR_CAPTURE="${MCPBASH_TOOL_STDERR_CAPTURE:-true}"

	# Increase stderr tail limit for more context in errors
	export MCPBASH_TOOL_STDERR_TAIL_LIMIT="${MCPBASH_TOOL_STDERR_TAIL_LIMIT:-8192}"
fi
