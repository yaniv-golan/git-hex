# git-hex

**Interactive git refactoring via MCP** — a focused toolset for rebase & commit perfection.

git-hex is an MCP (Model Context Protocol) server that provides AI assistants with safe, powerful git refactoring capabilities. It handles the complexity of interactive rebasing, fixup commits, and commit amendments while ensuring your repository is never left in a broken state.

## Features

- **Safe Rebasing**: Automatic abort on conflicts, always leaving your repo clean
- **Fixup Commits**: Create fixup! commits for later auto-squashing
- **Commit Amendments**: Safely amend the last commit with staged changes
- **Cherry-picking**: Single-commit cherry-pick with strategy options
- **Undo Support**: Built-in undo for all mutating operations via backup refs
- **Path Security**: All operations respect MCP roots for sandboxed access

## Requirements

- **mcp-bash framework** v0.4.0 or later
- **bash** 4.0+
- **jq** or **gojq**
- **git** 2.20+ (2.33+ recommended for `ort` merge strategy support)

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

## Common Workflows

These examples show how to combine git-hex tools for typical development tasks.

### Clean Up a Feature Branch After Code Review

After receiving review feedback, create targeted fixups and squash them:

```
1. Review current commits
   → gitHex.getRebasePlan { "onto": "main" }
   
2. For each piece of feedback:
   - Make the fix in your editor
   - Stage the changes: git add <files>
   - Create a fixup targeting the original commit:
     → gitHex.createFixup { "commit": "<hash-of-commit-to-fix>" }

3. Squash all fixups into their targets:
   → gitHex.performRebase { "onto": "main", "autosquash": true }
```

### Bring Your Branch Up to Date with Main

Rebase your feature branch onto the latest main:

```
1. First, update main:
   git checkout main && git pull

2. Switch back to your feature branch:
   git checkout feature/my-branch

3. Preview what will be rebased:
   → gitHex.getRebasePlan { "onto": "main" }

4. Perform the rebase:
   → gitHex.performRebase { "onto": "main" }
   
   If conflicts occur, git-hex automatically aborts and restores your branch.
   Resolve conflicts manually, then retry.
```

### Quick Fix to the Last Commit

Amend the most recent commit with additional changes:

```
1. Make your changes in the editor
2. Stage them: git add <files>
3. Amend:
   → gitHex.amendLastCommit { "addAll": true }
   
   Or with a new message:
   → gitHex.amendLastCommit { "message": "Better commit message" }
```

### Cherry-Pick a Single Fix from Another Branch

Bring one specific commit to your current branch:

```
1. Find the commit hash on the source branch:
   git log other-branch --oneline

2. Cherry-pick it:
   → gitHex.cherryPickSingle { "commit": "<hash>" }
   
   If conflicts occur, git-hex aborts automatically.
```

### Undo the Last git-hex Operation

Made a mistake? Undo it:

```
→ gitHex.undoLast {}

This restores HEAD to its state before the last git-hex operation.
Works for: amendLastCommit, createFixup, performRebase, cherryPickSingle
```

### When NOT to Use git-hex

- **On shared/protected branches** — Use on personal feature branches only
- **When you need complex rebase editing** — git-hex runs autosquash but doesn't support arbitrary reordering; use `git rebase -i` directly for that
- **On repos with contribution models you don't control** — Understand the project's rebase policy first

## Tools

### gitHex.getRebasePlan

Get a structured view of recent commits for rebase planning and inspection.

> **Note:** The `count` parameter limits how many commits are returned. When `onto` is not specified, the tool uses the upstream tracking branch if available, otherwise defaults to `HEAD~count`. This means `count` affects both the display limit *and* the default commit range. To inspect a specific range, always provide an explicit `onto` value.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository (defaults to single root) |
| `count` | integer | No | Number of commits (default: 10, max: 200) |
| `onto` | string | No | Base ref for commit range (defaults to upstream or HEAD~count) |

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
  "success": true,
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
  ],
  "summary": "Found 1 commits on feature/my-branch since main"
}
```

### gitHex.performRebase

Execute a rebase with automatic abort on conflict.

> **Prerequisites:** Working tree must be clean (no uncommitted changes). Commit or stash changes before running.

> **Note:** This tool rebases all commits in the range `onto..HEAD`. It runs in non-interactive mode with `--autosquash` support, meaning fixup/squash commits are automatically applied, but arbitrary reordering or dropping of commits is not supported. For manual reordering, use git directly.
>
> **Implementation detail:** Internally, this executes `git rebase -i --onto <onto> <onto>`, which replays all commits reachable from HEAD but not from `onto` onto the `onto` ref. The interactive mode is used with `GIT_SEQUENCE_EDITOR=true` to enable autosquash without manual intervention.

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
  "headBefore": "abc123...",
  "headAfter": "def456...",
  "summary": "Rebased 5 commits onto main",
  "commitsRebased": 5
}
```

### gitHex.createFixup

Create a fixup commit targeting a specific commit.

> **Prerequisites:** Changes must be staged (`git add`) before running. This tool commits the currently staged changes as a fixup.

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
  "headBefore": "def456...",
  "headAfter": "ghi789...",
  "targetCommit": "abc123...",
  "summary": "Created fixup commit ghi789 targeting abc123",
  "commitMessage": "fixup! Original commit message"
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

> **Note:** The `addAll` option stages only *tracked* files (`git add -u`), not new untracked files. This is a safety feature to prevent accidentally including unintended files. To include new files, stage them explicitly with `git add` before calling this tool.

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
  "headBefore": "abc123...",
  "headAfter": "jkl012...",
  "summary": "Amended commit with new hash jkl012",
  "commitMessage": "Updated commit message"
}
```

### gitHex.cherryPickSingle

Cherry-pick a single commit with configurable merge strategy.

> **Prerequisites:** Working tree must be clean (no uncommitted changes). Commit or stash changes before running.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `commit` | string | **Yes** | Commit hash/ref to cherry-pick |
| `strategy` | string | No | Merge strategy: recursive, ort, resolve |
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
  "headBefore": "def456...",
  "headAfter": "mno345...",
  "sourceCommit": "abc123...",
  "summary": "Cherry-picked abc123 as new commit mno345",
  "commitMessage": "Original commit subject line"
}
```

### gitHex.undoLast

Undo the last git-hex operation by resetting to the backup ref.

> **Prerequisites:** Working tree must be clean (no uncommitted changes). Commit or stash changes before running.

Every mutating git-hex operation (amend, fixup, rebase, cherry-pick) automatically creates a backup ref before making changes. This tool restores the repository to that state.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |

**Example:**
```json
{}
```

**Returns:**
```json
{
  "success": true,
  "headBefore": "mno345...",
  "headAfter": "def456...",
  "undoneOperation": "cherryPickSingle",
  "backupRef": "git-hex/backup/1234567890_cherryPickSingle",
  "commitsUndone": 1,
  "summary": "Undid cherryPickSingle from 2024-01-15 10:30:00. Reset 1 commit(s) from mno345 to def456"
}
```

## Safety Features

git-hex is designed with safety as a priority:

1. **Conflict Handling**: All operations that can cause conflicts (rebase, cherry-pick) automatically abort and restore the repository to its original state if conflicts occur.

2. **State Validation**: Tools check for uncommitted changes, existing rebase/cherry-pick states, and other conditions before proceeding.

3. **Cleanup Traps**: Shell traps ensure cleanup happens even on unexpected errors.

4. **Path Validation**: When MCP roots are configured, all paths are validated to stay within allowed boundaries.

5. **Backup Refs**: Every mutating operation creates a backup ref (`refs/git-hex/backup/<timestamp>_<operation>`) before making changes. Use `gitHex.undoLast` to restore or manually reset with `git reset --hard refs/git-hex/last/<timestamp>_<operation>`.

## Recovery

### Using gitHex.undoLast

The easiest way to recover from an unwanted operation:

```json
// Undo the last git-hex operation
{ "tool": "gitHex.undoLast", "arguments": {} }
```

### Using Git Reflog (Manual Recovery)

If you need to recover beyond the last operation, or if `undoLast` isn't available:

```bash
# View recent HEAD positions
git reflog

# Find the commit before the unwanted operation
# Look for entries like "rebase (start)" or your original commit

# Reset to that state
git reset --hard HEAD@{2}  # or use the commit hash
```

### Using git-hex Backup Refs

git-hex stores backup refs that persist across sessions:

```bash
# List all git-hex backup refs
git for-each-ref refs/git-hex/

# Reset to a specific backup
git reset --hard refs/git-hex/backup/1234567890_performRebase
```

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

