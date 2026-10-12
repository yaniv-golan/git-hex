# git-hex Server Configuration

This directory contains mcp-bash framework configuration files.

## Files

### env.sh
Optional debug settings for local runs. The server never loads it; only `mcp-bash run-tool --with-server-env` does. Which variables tools receive is declared in `server.meta.json` (below).

**Debug mode**: When `MCPBASH_LOG_LEVEL=debug`:
- Enables `MCPBASH_TOOL_STDERR_CAPTURE`
- Sets `MCPBASH_TOOL_STDERR_TAIL_LIMIT=8192`

### health-checks.sh
Validates external dependencies before serving.

**Checks**:
- `git` command availability
- Git version warning if < 2.20 (2.33+ recommended for ort merge strategy)

### policy.sh
Defines `mcp_tools_policy_project`, the restrict-only hook mcp-bash runs after its own allowlist and path checks; it implements read-only mode. A blocked call returns an error result with type `policy_denied` and the read-only message.

**Behavior**: When `GIT_HEX_READ_ONLY=1`, blocks:
- `git-hex-rebaseWithPlan`
- `git-hex-splitCommit`
- `git-hex-createFixup`
- `git-hex-amendLastCommit`
- `git-hex-cherryPickSingle`
- `git-hex-resolveConflict`
- `git-hex-continueOperation`
- `git-hex-abortOperation`
- `git-hex-undoLast`

### register.json
Declarative registration of completions, resources, and prompts.

**Completions**:
- `git-ref` - Git references (branches, tags)
- `commit-sha` - Commit SHAs with messages
- `conflict-path` - Files with conflicts

### requirements.json
Framework and dependency version requirements.

**Requirements**:
- mcp-bash >= 1.8.0 (the server runs on the vendored runtime in `.mcp-bash/`)
- bash >= 3.2.0
- git >= 2.20.0 (2.33.0 recommended)
- jq or gojq

### server.meta.json
Server metadata (name, version, description), the mcp-bash API version, and the tool env policy: tools run in `allowlist` mode and receive `GIT_HEX_DEBUG`, `GIT_HEX_DEBUG_SPLIT` and `GIT_HEX_DEBUG_REBASE`.

## Debug Mode

Enable via `server.d/.debug` file (mcp-bash 0.9.5+ native detection):
```bash
touch server.d/.debug   # Enable
rm server.d/.debug      # Disable
```

Or via environment:
```bash
GIT_HEX_DEBUG=1 ./git-hex.sh
```
