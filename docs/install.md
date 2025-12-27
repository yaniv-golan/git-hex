# Installation

## Claude Code users

Install directly from GitHub—no clone required:

```text
/plugin marketplace add yaniv-golan/git-hex
/plugin install git-hex@git-hex-marketplace
```

## MCP config users (Cursor, Claude Desktop, Windsurf)

### Step 1: Clone and set up

```bash
git clone https://github.com/yaniv-golan/git-hex.git ~/git-hex
cd ~/git-hex
./git-hex.sh install
```

This installs the mcp-bash framework. Use `./git-hex.sh doctor` to check prerequisites without modifying anything.

### Step 2: Verify installation

```bash
./git-hex.sh validate
```

For thorough validation including strict MCP client checks (requires Node.js):

```bash
./git-hex.sh validate --inspector
```

### Step 3: Configure your MCP client

#### Cursor

Create `.cursor/mcp.json` in your project directory:

```json
{
  "mcpServers": {
    "git-hex": {
      "command": "~/git-hex/git-hex.sh"
    }
  }
}
```

Then restart Cursor to load the MCP server.

#### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "git-hex": {
      "command": "~/git-hex/git-hex.sh"
    }
  }
}
```

Then restart Claude Desktop.

#### Windsurf

Add to your Windsurf MCP configuration (see Windsurf docs for location):

```json
{
  "mcpServers": {
    "git-hex": {
      "command": "~/git-hex/git-hex.sh"
    }
  }
}
```

> **Tip:** If you see "command not found" errors for `git` or `jq`, use `git-hex-env.sh` instead—it sources your shell profile to pick up PATH settings.

### Step 4: Verify MCP connection

After configuring, verify the server connects:

1. Restart your MCP client (Cursor/Claude Desktop/Windsurf)
2. Open a git repository
3. Ask the AI to "list the available git-hex tools"

If the connection fails, see [Troubleshooting](troubleshooting.md).

## What `install` may write (managed default install)

When `MCPBASH_HOME` is **not** set, `git-hex.sh` manages the MCP Bash Framework install at:

- `${XDG_DATA_HOME:-$HOME/.local/share}/mcp-bash`

During `install`, it may:

- Create/replace the framework directory at the managed path above (via a staged/atomic directory swap).
- Create a convenience launcher at `${HOME}/.local/bin/mcp-bash` (symlink when possible; otherwise a small shim script).
- Create temporary staging directories alongside the target (e.g., `mcp-bash.stage.*`) during install.

It does **not** modify your git configuration or repositories during install.

### User-managed installs (`MCPBASH_HOME`)

If `MCPBASH_HOME` is set, that install is treated as user-managed:

- `./git-hex.sh doctor` will use it.
- `./git-hex.sh install` will refuse to modify it (policy refusal), and will instruct you to upgrade it yourself.

## Verified framework install (recommended for CI / supply-chain conscious setups)

Set a checksum to force a verified tarball install of the pinned framework version:

```bash
export GIT_HEX_MCPBASH_SHA256="1052410873fec2bfbc42346a93c3a89aa38ff0e3eac7135475ec556e58cc85cd"
./git-hex.sh install
```

By default, `git-hex.sh` downloads the GitHub tag archive for `FRAMEWORK_VERSION` (e.g., `https://github.com/yaniv-golan/mcp-bash-framework/archive/refs/tags/v0.8.3.tar.gz`).

Optional: override the archive URL used with `GIT_HEX_MCPBASH_ARCHIVE_URL` if you mirror artifacts or publish your own release assets.

## Network behavior (scoped)

- During tool execution on a repository, git-hex does not need network access.
- Installation/upgrade of the MCP Bash Framework may use the network (download tarball or clone a pinned commit) unless you preinstall/manage it yourself.

## Uninstall / cleanup

### Remove git-hex

```bash
rm -rf ~/git-hex
```

### Remove the managed framework install (only if you used the managed default)

```bash
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/mcp-bash"
rm -f "${HOME}/.local/bin/mcp-bash"
```

If you set `MCPBASH_HOME`, remove that install according to how you manage it.
