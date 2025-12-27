# Changelog

All notable changes to git-hex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Auto-install of pinned MCP Bash Framework
- Docker support
- Claude Code plugin with Skills for branch cleanup, conflict resolution, and PR workflows

[Unreleased]: https://github.com/yaniv-golan/git-hex/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yaniv-golan/git-hex/releases/tag/v0.1.0
