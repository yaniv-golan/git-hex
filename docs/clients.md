# Client setup

## Claude Code plugin

git-hex is an MCP server. Claude Code users can install it via the plugin, which bundles companion Skills:

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

### Verify it’s working

In your AI chat (in a Git repo under your allowed folders), ask:

> “Show me the last 5 commits I could rebase onto `main`.”

When connected, the AI should be able to use tools like `git-hex-getRebasePlan` to answer. If the tools aren’t available or repo access is denied, check:
- allowed folders (MCP `roots`): [`concepts.md`](concepts.md#allowed-folders-mcp-roots)
- launcher choice (macOS apps launched from Finder/Spotlight/Dock): use `git-hex-env.sh` (see below)

Allowed folders guidance:
- Configure your client’s allowed folders (MCP `roots` / `allowedRoots`) to limit filesystem access. See [`concepts.md`](concepts.md#allowed-folders-mcp-roots).
- With one allowed folder, `repoPath` may default to that folder; with multiple allowed folders, pass `repoPath` explicitly. See [`concepts.md`](concepts.md#repopath).

### Choose a launcher

- `git-hex.sh` — default launcher. Requires framework pre-installed via `./git-hex.sh install`. Sets `MCPBASH_PROJECT_ROOT`. **Use this for all clients.**
- `git-hex-env.sh` — fallback launcher that sources your login profile first. Use if you see "command not found" errors for `git`, `jq`, etc.

### Troubleshooting PATH issues

If you see "command not found" errors in GUI clients (Cursor, Claude Desktop, etc.):

1. **Try `git-hex-env.sh`** instead of `git-hex.sh`
2. It sources your login profile (`~/.zprofile`, `~/.bash_profile`) before starting
3. By default, it silences profile output to avoid corrupting stdio; set `GIT_HEX_ENV_SILENCE_PROFILE_OUTPUT=0` to disable

### Quick commands

- MCP Inspector (from the repo root): `./git-hex.sh config --inspector`
- Claude Code/CLI (stdio): `claude mcp add --transport stdio git-hex --env MCPBASH_PROJECT_ROOT="$PWD" -- "$PWD/git-hex.sh"`
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
