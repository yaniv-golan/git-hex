#!/usr/bin/env bash
set -euo pipefail

# Wrapper to force compact JSON output (-c) to avoid Windows/MSYS E2BIG issues
# when mcp-bash passes large JSON blobs via --argjson on the command line.
exec jq -c "$@"
