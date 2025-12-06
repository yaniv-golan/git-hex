# Changelog

All notable changes to git-hex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- Initial release of git-hex MCP server
- **gitHex.getRebasePlan** - Get structured rebase plan for last N commits
- **gitHex.performRebase** - Execute interactive rebase with auto-abort on conflict
- **gitHex.createFixup** - Create fixup commits for later auto-squashing
- **gitHex.amendLastCommit** - Amend last commit with staged changes or new message
- **gitHex.cherryPickSingle** - Cherry-pick single commit with strategy options
- Automatic cleanup on conflicts (rebase/cherry-pick abort)
- MCP roots enforcement for path security
- Docker support
- Comprehensive documentation

### Security

- All path arguments validated against MCP roots
- Repository state validated before destructive operations
- Cleanup traps ensure repos are never left in broken state

[0.1.0]: https://github.com/yaniv-golan/git-hex/releases/tag/v0.1.0
