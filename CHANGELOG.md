# Changelog

All notable changes to git-hex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/yaniv-golan/git-hex/releases/tag/v0.1.0
