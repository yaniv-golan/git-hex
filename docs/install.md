# Installation

## MCPB Bundle (Single-File Distribution)

For MCPB-compatible clients (Claude Desktop and others supporting the MCPB format):

1. Download the latest `.mcpb` bundle from [GitHub Releases](https://github.com/yaniv-golan/git-hex/releases)
2. Double-click the `.mcpb` file or drag it to your MCPB-compatible client
3. The server will be automatically installed and configured

To build the bundle yourself:
```bash
git clone https://github.com/yaniv-golan/git-hex.git
cd git-hex
make bundle
# Creates git-hex-<version>.mcpb
```

## Claude Code users

Install directly from GitHub—no clone required:

```text
/plugin marketplace add yaniv-golan/git-hex
/plugin install git-hex@git-hex-marketplace
```

## MCP config users (Cursor, Claude Desktop, Windsurf)

### Prerequisites

- `bash` 3.2+
- `git`
- `jq` or `gojq`

### Step 1: Clone

```bash
git clone https://github.com/yaniv-golan/git-hex.git ~/git-hex
```

No install step is needed — the mcp-bash runtime is vendored in the repository.

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

## Upgrading the vendored runtime

The mcp-bash runtime is vendored in `.mcp-bash/` and checked into the repository. To upgrade it:

```bash
mcp-bash vendor --upgrade
```

This fetches the latest compatible mcp-bash release and updates the vendored copy. Commit the result to lock the new version into source control.

## Network behavior

git-hex does not need network access during tool execution or server startup. The runtime is vendored locally. Network access is only needed when cloning the repository or upgrading the vendored runtime.

## Uninstall

```bash
rm -rf ~/git-hex
```

Then remove the `git-hex` entry from your MCP client configuration file.
