# git-hex

**Interactive git refactoring via MCP** — a focused toolset for rebase & commit perfection.

git-hex is an MCP (Model Context Protocol) server that provides AI assistants with safe, powerful git refactoring capabilities. It handles the complexity of interactive rebasing, fixup commits, and commit amendments while ensuring your repository is never left in a broken state.

## Features

- **Safe Rebasing**: Automatic abort on conflicts, always leaving your repo clean
- **Fixup Commits**: Create fixup! commits for later auto-squashing
- **Commit Amendments**: Safely amend the last commit with staged changes
- **Cherry-picking**: Single-commit cherry-pick with strategy options
- **Path Security**: All operations respect MCP roots for sandboxed access

## Requirements

- **mcp-bash framework** v0.4.0 or later
- **bash** 4.0+
- **jq** or **gojq**
- **git** 2.20+

## Installation

### Quick Start (Recommended)

```bash
# Clone git-hex
git clone https://github.com/yaniv-golan/git-hex.git ~/git-hex

# Install mcp-bash framework (if not already installed)
curl -fsSL https://raw.githubusercontent.com/yaniv-golan/mcp-bash-framework/main/install.sh | bash
```

### Using the Wrapper Script

git-hex includes a `run.sh` wrapper that auto-installs the framework:

```bash
git clone https://github.com/yaniv-golan/git-hex.git ~/git-hex
cd ~/git-hex
./run.sh  # Auto-installs framework on first run
```

## MCP Client Configuration

### Claude Desktop / Cursor / Windsurf

Add to your MCP client configuration:

```json
{
  "mcpServers": {
    "git-hex": {
      "command": "/path/to/mcp-bash-framework/bin/mcp-bash",
      "env": {
        "MCPBASH_PROJECT_ROOT": "/path/to/git-hex"
      }
    }
  }
}
```

Or using the wrapper script:

```json
{
  "mcpServers": {
    "git-hex": {
      "command": "/path/to/git-hex/run.sh"
    }
  }
}
```

### Windows (Git Bash)

```json
{
  "mcpServers": {
    "git-hex": {
      "command": "C:\\Program Files\\Git\\bin\\bash.exe",
      "args": ["-c", "/c/Users/me/git-hex/run.sh"],
      "env": {
        "MCPBASH_PROJECT_ROOT": "/c/Users/me/git-hex",
        "MSYS2_ARG_CONV_EXCL": "*"
      }
    }
  }
}
```

## Tools

### gitHex.getRebasePlan

Get a structured rebase plan for the last N commits.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository (defaults to single root) |
| `count` | integer | No | Number of commits (default: 10, max: 200) |
| `onto` | string | No | Base ref to rebase onto |

**Example:**
```json
{
  "repoPath": "/path/to/repo",
  "count": 5
}
```

**Returns:**
```json
{
  "plan_id": "plan_1234567890_12345",
  "branch": "feature/my-branch",
  "onto": "main",
  "commits": [
    {
      "hash": "abc123...",
      "shortHash": "abc123",
      "subject": "Add feature X",
      "author": "Developer",
      "date": "2024-01-15T10:30:00Z"
    }
  ]
}
```

### gitHex.performRebase

Execute an interactive rebase with automatic abort on conflict.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `onto` | string | **Yes** | Base ref to rebase onto |
| `autosquash` | boolean | No | Auto-squash fixup! commits (default: true) |

**Example:**
```json
{
  "onto": "main",
  "autosquash": true
}
```

**Returns:**
```json
{
  "success": true,
  "message": "Successfully rebased 5 commits onto main",
  "newHead": "def456...",
  "commitsRebased": 5
}
```

### gitHex.createFixup

Create a fixup commit targeting a specific commit.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `commit` | string | **Yes** | Commit hash/ref to create fixup for |
| `message` | string | No | Additional message to append |

**Example:**
```json
{
  "commit": "abc123",
  "message": "Fix typo in function name"
}
```

**Returns:**
```json
{
  "success": true,
  "fixupHash": "ghi789...",
  "targetCommit": "abc123...",
  "message": "fixup! Original commit message"
}
```

### gitHex.amendLastCommit

Amend the last commit with staged changes and/or a new message.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `message` | string | No | New commit message |
| `addAll` | boolean | No | Stage all tracked modified files (default: false) |

**Example:**
```json
{
  "message": "Updated commit message",
  "addAll": true
}
```

**Returns:**
```json
{
  "success": true,
  "newHash": "jkl012...",
  "previousHash": "abc123...",
  "message": "Updated commit message"
}
```

### gitHex.cherryPickSingle

Cherry-pick a single commit with configurable merge strategy.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `commit` | string | **Yes** | Commit hash/ref to cherry-pick |
| `strategy` | string | No | Merge strategy: recursive, ort, resolve, octopus |
| `noCommit` | boolean | No | Apply without committing (default: false) |

**Example:**
```json
{
  "commit": "abc123",
  "strategy": "ort"
}
```

**Returns:**
```json
{
  "success": true,
  "newHash": "mno345...",
  "sourceCommit": "abc123...",
  "message": "Successfully cherry-picked abc123"
}
```

## Safety Features

git-hex is designed with safety as a priority:

1. **Conflict Handling**: All operations that can cause conflicts (rebase, cherry-pick) automatically abort and restore the repository to its original state if conflicts occur.

2. **State Validation**: Tools check for uncommitted changes, existing rebase/cherry-pick states, and other conditions before proceeding.

3. **Cleanup Traps**: Shell traps ensure cleanup happens even on unexpected errors.

4. **Path Validation**: When MCP roots are configured, all paths are validated to stay within allowed boundaries.

## Testing

```bash
# Validate project structure (run from project root)
cd /path/to/git-hex
mcp-bash validate

# Test a tool directly
mcp-bash run-tool gitHex.getRebasePlan --roots /path/to/test/repo --args '{"count": 5}'

# Run with MCP Inspector (must be run from project root or use ./run.sh)
cd /path/to/git-hex
npx @modelcontextprotocol/inspector --transport stdio -- mcp-bash

# Alternative: use run.sh wrapper (works from any directory)
npx @modelcontextprotocol/inspector --transport stdio -- /path/to/git-hex/run.sh
```

> **Note:** The `mcp-bash` command auto-detects the project root when run from within the git-hex directory. If running from elsewhere, either use the `./run.sh` wrapper or set `MCPBASH_PROJECT_ROOT=/path/to/git-hex`.

## Docker

```bash
docker build -t git-hex .
docker run -i --rm -v /path/to/repos:/repos git-hex
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please ensure:
- All tools pass `mcp-bash validate`
- New tools follow the naming convention (`gitHex.toolName`)
- Tests are included for new functionality

## Related Projects

- [mcp-bash-framework](https://github.com/yaniv-golan/mcp-bash-framework) - The MCP server framework powering git-hex
- [Model Context Protocol](https://modelcontextprotocol.io/) - The protocol specification

