# Changelog

All notable changes to git-hex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- `gitHex.undoLast` now refuses to reset if new commits were made after the backup unless `force=true`.
- Backup ref reporting now matches the specific `last` ref used for undo.
- `resolveConflict` allows Unicode paths and rejects Windows drive-letter style paths for clarity.
- Tool schemas align with emitted `error` fields and mark required inputs where applicable.
- Auto-stash keep-index mode stores stash object IDs instead of symbolic refs.
- README clarifies undo semantics, roots expectations, and Git version requirements.

## [0.1.0] - 2025-12-07

### Added

- **gitHex.undoLast** - Undo the last git-hex operation via backup refs
- Backup ref system (`refs/git-hex/backup/`) for all mutating operations
- Recovery documentation with reflog and backup ref examples
- Initial release of git-hex MCP server
- **gitHex.getRebasePlan** - Get structured rebase plan for last N commits
- **gitHex.rebaseWithPlan** - Structured interactive rebase with autosquash/autostash support
- **gitHex.createFixup** - Create fixup commits for later auto-squashing
- **gitHex.amendLastCommit** - Amend last commit with staged changes or new message
- **gitHex.cherryPickSingle** - Cherry-pick single commit with strategy options
- Automatic cleanup on conflicts (rebase/cherry-pick abort)
- MCP roots enforcement for path security
- Docker support
- Comprehensive documentation
- Consistent API output fields across all tools:
  - `headBefore`/`headAfter` for tracking commit changes
  - `summary` for human-readable text, `commitMessage` for git subjects
  - All tools return `success` field
- Clear error messages for GPG signing, git hooks, and conflicts

### Security

- All path arguments validated against MCP roots
- Repository state validated before destructive operations
- Cleanup traps ensure repos are never left in broken state

[Unreleased]: https://github.com/yaniv-golan/git-hex/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yaniv-golan/git-hex/releases/tag/v0.1.0
