# Client setup

## Claude Code plugin

git-hex ships as a Claude Code plugin with bundled Skills:

- `skills/git-hex-branch-cleanup/SKILL.md`
- `skills/git-hex-conflict-resolution/SKILL.md`
- `skills/git-hex-pr-workflow/SKILL.md`

Installation (Claude Code):

```text
# From the parent directory of this repo:
/plugin marketplace add ./git-hex
/plugin install git-hex@git-hex-marketplace

# Or from GitHub:
/plugin marketplace add yaniv-golan/git-hex
/plugin install git-hex@git-hex-marketplace
```

### Updating

git-hex (as a third-party plugin) does not auto-update by default. To update, use these slash commands in Claude Code:

- Manual update: `/plugin marketplace update git-hex-marketplace`
- Enable auto-update: `/plugin` → select Marketplaces → git-hex-marketplace → Enable auto-update

See Plugin Marketplaces docs: https://code.claude.com/docs/en/plugin-marketplaces

### Claude command templates

The repo includes Claude Code command templates under `claude-commands/` (e.g., `git-hex-cleanup`, `git-hex-status`). They are meant to be used by Claude Code as command definitions, not end-user documentation.

## MCP client configuration (Cursor, Windsurf, Claude Desktop/CLI)

Recommended:

```json
{
  "mcpServers": {
    "git-hex": {
      "command": "/path/to/git-hex/git-hex.sh"
    }
  }
}
```

Roots guidance:
- Configure MCP `roots`/`allowedRoots` to limit filesystem access.
- With one configured root, `repoPath` defaults to that root; with multiple roots, pass `repoPath` explicitly.

### Choose a launcher

- `git-hex.sh` — default launcher. Auto-installs/pins the framework and sets `MCPBASH_PROJECT_ROOT`. Use for terminals/CLI.
- `git-hex-env.sh` — login-aware launcher (sources your login profile first). Use for GUI clients that miss PATH/version managers (e.g., macOS Claude Desktop).

### Quick commands

- MCP Inspector (from the repo root): `./git-hex.sh config --inspector`
- Claude Code/CLI (stdio): `claude mcp add --transport stdio git-hex --env MCPBASH_PROJECT_ROOT="$PWD" -- "$PWD/git-hex.sh"` (use `git-hex-env.sh` for macOS GUI shells)
- Cursor: add the JSON to `~/.cursor/mcp.json` or a project `.cursor/mcp.json`

### Windows (Git Bash)

```json
{
  "mcpServers": {
    "git-hex": {
      "command": "C:\\\\Program Files\\\\Git\\\\bin\\\\bash.exe",
      "args": ["-c", "/c/Users/me/git-hex/git-hex.sh"],
      "env": {
        "MCPBASH_PROJECT_ROOT": "/c/Users/me/git-hex",
        "MSYS2_ARG_CONV_EXCL": "*"
      }
    }
  }
}
```

Windows notes:
- If path arguments are being mangled by MSYS, keep `MSYS2_ARG_CONV_EXCL="*"` for the MCP server environment.
- If you hit JSON tooling issues, install `jq` and set `MCPBASH_JSON_TOOL=jq` in the server environment.
