# CI Guidance for git-hex and MCP Bash Framework

These tips help keep CI runs reliable and easy to debug, especially on Windows hosted runners where long PATH/env values can break `gojq`.

## JSON tool selection
- The framework prefers `jq` when available; on Windows runners, set:
  - `MCPBASH_JSON_TOOL=jq`
  - `MCPBASH_JSON_TOOL_BIN=jq`
- If `gojq` is your only option, verify it runs with `gojq --version`. Exec failures (`Argument list too long`) usually mean the env/PATH is too large.

## Recommended CI env
- Minimal essentials: ensure `mcp-bash`, `git`, and `jq` are on PATH.
- Reduce noisy debug flags unless needed (`MCPBASH_TRACE_TOOLS`, extra logging) to keep env size down on Windows.
- Set `MCPBASH_PROJECT_ROOT` to the repo root; set `MCPBASH_HOME` if using a custom framework install.

## Pre-flight sanity checks
- Run `mcp-bash validate` before integration tests.
- If using Windows hosted runners, prefer `jq` to avoid gojq exec limits.
- Inspect `test/integration` env snapshot (`failure-summary.txt` references) for PATH length and selected JSON tool.

## Example (GitHub Actions, Windows)
```yaml
env:
  MCPBASH_JSON_TOOL: jq
  MCPBASH_JSON_TOOL_BIN: jq
  MCPBASH_PROJECT_ROOT: ${{ github.workspace }}
  GITHEX_INTEGRATION_TMP: ${{ runner.temp }}/githex-integration
  MCPBASH_LOG_DIR: ${{ runner.temp }}/mcpbash-logs

steps:
  - uses: actions/checkout@v4
  - run: mcp-bash validate
  - run: ./test/integration/run.sh
```

## Troubleshooting
- Tools fail with “Argument list too long” or “tool not found”: switch to `jq` and trim PATH/env.
- CRLF warnings from git during fixture setup are harmless but can be reduced by disabling `core.autocrlf` in CI.
- If `validate` warns about missing JSON tooling, install jq or set the vars above to point to an existing jq/gojq.
