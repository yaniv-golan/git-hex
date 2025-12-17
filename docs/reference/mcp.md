# MCP details

This page collects MCP/framework-specific details that are not required for day-to-day use.

## MCP Spec Coverage

Targets the MCP protocol as implemented/negotiated by the MCP Bash Framework (version negotiation and client downgrades handled by the framework).

| Category | Coverage | Notes |
|----------|----------|-------|
| Core | ✅ Full | Lifecycle, ping, capabilities via framework |
| Tools | ✅ Full | git-hex tool suite (see `docs/reference/tools.md`) |
| Resources | ✅ Templates | `resources/templates/list` returns templates discovered from `resources/*.meta.json` (`uriTemplate`). Note: framework capabilities don’t currently advertise templates, so some clients may not discover them automatically. |
| Prompts | ✅ Some | Workflow prompts under `prompts/` (listed via `prompts/list`) |
| Completions | ✅ Providers | Completion providers registered via `server.d/register.json` (full mode requires jq/gojq) |

## MCP Details

- Capabilities: git-hex exposes MCP tools, completion providers, resource templates, and workflow prompts. Note: framework capabilities don’t currently advertise templates even though `resources/templates/list` is implemented.
- Error codes: invalid arguments and read-only mode blocks use `-32602`; unexpected failures use `-32603`. Tool summaries include human-readable hints.
- Read-only mode: controlled by `GIT_HEX_READ_ONLY=1` (see `docs/safety.md`).
- Initialization: uses the MCP Bash Framework defaults; capability negotiation simply advertises the tool list.

### Using with MCP clients

Minimal stdio configuration (client JSON varies; start with the wrapper and add roots per your client):
```json
{
  "mcpServers": {
    "git-hex": {
      "command": "/path/to/git-hex/git-hex.sh"
    }
  }
}
```

If launching from a GUI login shell on macOS, prefer `git-hex-env.sh` so PATH/env matches your login shell. Always configure your client’s `roots`/`allowedRoots` (name varies by client) to the repositories you want the tools to touch.

### Environment flags

| Variable | Default | Effect |
|----------|---------|--------|
| `MCPBASH_PROJECT_ROOT` | (auto when running `git-hex.sh`) | Path to this repo; required if you invoke `mcp-bash` directly. |
| `GIT_HEX_READ_ONLY` | unset | `1` blocks mutating tools (read-only mode). |
| `GIT_HEX_DEBUG` | unset | `true` enables shell tracing in tools. |
| `GIT_HEX_DEBUG_SPLIT` | unset | `true` dumps splitCommit debug JSON to `${TMPDIR:-/tmp}/git-hex-split-debug.json`. |
| `MCPBASH_CI_MODE` | unset | `1` uses CI-safe defaults in tests (set automatically in CI). |
| `MCPBASH_TRACE_TOOLS` | unset | Set to enable per-command tracing in tools (see `MCPBASH_TRACE_PS4`). |
