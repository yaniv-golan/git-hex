# Changelog

All notable changes to git-hex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Friendly error responses for Claude Desktop**: Tool errors now return structured JSON responses instead of MCP protocol errors. This allows Claude to explain errors naturally instead of showing generic "Failed to call tool" banners.

  Error response format:
  ```json
  {
    "success": false,
    "error": {
      "code": "REBASE_IN_PROGRESS",
      "message": "Repository is in a rebase state.",
      "suggestions": ["Use getConflictStatus to check status", "..."]
    }
  }
  ```

  All tool `outputSchema` definitions updated with `oneOf` discriminated union to include error case.

- Upgraded to mcp-bash framework v1.1.0
  - v1.1.0: MCP Apps UI resources support
  - v0.12.0: Timeout errors now use `isError: true` format with structured metadata
  - v0.11.0: New `--array-path` parameter for `mcp_json_truncate`
  - v0.10.0: SDK helpers `mcp_config_load/get`, `mcp_download_safe`, `mcp_result_text_with_resource`
  - Bug fixes for JSON escaping, gojq compatibility, and debug redaction
  - See [mcp-bash CHANGELOG](https://github.com/yaniv-golan/mcp-bash-framework/blob/main/CHANGELOG.md) for details

### Added

- **MCP Apps UI resources** for read-only tools:
  - `git-hex-getConflictStatus` - Tab-based diff viewer for conflict resolution
  - `git-hex-checkRebaseConflicts` - Conflict prediction visualization
  - `git-hex-getRebasePlan` - Commit timeline with action indicators

- New shared error handling functions in `lib/git-helpers.sh`:
  - `git_hex_error_json()` - Generate structured error JSON
  - `git_hex_error()` - Output error and exit cleanly
  - Predefined error codes (e.g., `REBASE_IN_PROGRESS`, `INVALID_COMMIT`, `UNCOMMITTED_CHANGES`)

## [0.1.0] - 2025-12-26

Initial public release.

### Tools

- **git-hex-getRebasePlan** — Structured rebase plan for commit inspection
- **git-hex-rebaseWithPlan** — Interactive rebase with plan support (reorder, squash, drop, reword)
- **git-hex-checkRebaseConflicts** — Dry-run conflict prediction (Git 2.38+)
- **git-hex-splitCommit** — Split a commit into multiple commits by file
- **git-hex-createFixup** — Create fixup! commits for auto-squashing
- **git-hex-amendLastCommit** — Amend last commit with staged changes or new message
- **git-hex-cherryPickSingle** — Cherry-pick single commit with strategy options
- **git-hex-undoLast** — Undo the last git-hex operation via backup refs
- **git-hex-getConflictStatus** — Detect paused operations and conflicting files
- **git-hex-resolveConflict** — Mark conflicted files as resolved
- **git-hex-continueOperation** — Continue paused rebase/merge/cherry-pick
- **git-hex-abortOperation** — Abort and restore original state

### Features

- Backup ref system (`refs/git-hex/backup/`) for all history-mutating operations
- Automatic abort on conflicts (configurable via `abortOnConflict`)
- MCP roots enforcement for path security
- Read-only mode (`GIT_HEX_READ_ONLY=1`)
- Pinned MCP Bash Framework (install via `./git-hex.sh install`)
- Docker support
- Claude Code plugin with Skills for branch cleanup, conflict resolution, and PR workflows

[Unreleased]: https://github.com/yaniv-golan/git-hex/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yaniv-golan/git-hex/releases/tag/v0.1.0
