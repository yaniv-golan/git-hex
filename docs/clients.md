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

- `git-hex.sh` — default launcher. Requires framework pre-installed via `./git-hex.sh install`. Sets `MCPBASH_PROJECT_ROOT`. Use for terminals/CLI.
- `git-hex-env.sh` — login-aware launcher (sources your login profile first). Use for GUI clients that miss PATH/version managers (e.g., macOS Claude Desktop).

### macOS apps launched from Finder/Spotlight/Dock and PATH

On macOS, apps launched from Finder/Spotlight/Dock can start with a limited environment (PATH/version managers not loaded), because they are not launched from your Terminal session.

Common symptoms:
- `git: command not found` (or a different `git` than in Terminal)
- `jq: command not found`
- `node: command not found` / wrong version (asdf/nvm/pyenv not loaded)

Recommended fix:
- Use `git-hex-env.sh` for macOS GUI apps. It sources your login profile (e.g., `~/.zprofile`, `~/.bash_profile`) before starting the server so PATH/tooling matches your Terminal setup.
- By default, it silences profile output to avoid corrupting stdio-based MCP sessions; set `GIT_HEX_ENV_SILENCE_PROFILE_OUTPUT=0` to disable.

### Quick commands

- MCP Inspector (from the repo root): `./git-hex.sh config --inspector`
- Claude Code/CLI (stdio): `claude mcp add --transport stdio git-hex --env MCPBASH_PROJECT_ROOT="$PWD" -- "$PWD/git-hex.sh"` (use `git-hex-env.sh` for macOS apps launched from Finder/Spotlight/Dock)
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
