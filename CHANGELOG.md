# Changelog

All notable changes to git-hex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **A tool that times out returns the same error shape as every other error** (from mcp-bash 1.9.1): `_meta["mcpbash/error"]` with type `timeout`, and no `structuredContent`. Before, it returned `structuredContent: {"success": false, "error": {...}}`, which doesn't match the tool's `outputSchema` (the known issue in 0.4.0). The timeout hint now follows `Hint:` instead of `Suggestion:`.

### Changed

- **Vendored mcp-bash runtime upgraded from 1.9.0 to 1.9.1**, and the Docker image uses 1.9.1. Also from 1.9.1: reading a resource by URI no longer reports it missing when two resources share the URI.
- **CI installs a pinned mcp-bash CLI**: the workflows install the mcp-bash release that the `Dockerfile` pins, check it against the pinned checksum, and fail if it differs from the vendored runtime in `.mcp-bash/`. They used to install whatever was on mcp-bash's `main` branch, so an mcp-bash change could break git-hex CI without any git-hex change.

## [0.4.0] - 2026-10-12

### Behaviour changes to check before upgrading

- **Tool results no longer have a `{success, result}` envelope**: `structuredContent` is the result object itself (for example `{"headBefore": ..., "headAfter": ..., "summary": ...}`), and each tool's `outputSchema` describes that object. Clients or scripts that read `.result.<field>` or check `.success` must read the fields directly. The MCP Apps views already accept both shapes.
- **Errors are error results (`isError: true`)**: a refused or failed call used to be a normal result whose structured content was `{"success": false, "error": {...}}`. It is now an error result: the text is the message (with a `Hint:` line when there are suggestions), and `_meta["mcpbash/error"]` holds `type` (the error code in lower case, e.g. `rebase_in_progress`), `message`, `hint` and `data` (`code` and `suggestions`). See the Errors section of [`docs/reference/tools.md`](docs/reference/tools.md#errors).
- **Read-only and allowlist denials are error results too**: a call refused by `MCPBASH_TOOL_ALLOWLIST` or by read-only mode (`GIT_HEX_READ_ONLY=1`) returns an error result with type `policy_denied` and the denial message.
- **Tools are stopped when the server stops abnormally** (from mcp-bash 1.9): if the client quits or the connection breaks while a tool runs, the tool gets TERM, then KILL after 1 second. A rebase, cherry-pick or merge stopped this way stays in progress: check with `git-hex-getConflictStatus`, then `git-hex-continueOperation` or `git-hex-abortOperation`, or restore the backup with `git-hex-undoLast`.

### Changed

- **Vendored mcp-bash runtime upgraded from 1.6.0 to 1.9.0** (from the verified v1.9.0 release tarball). Tools use the 2.0-stable helpers (`mcp_result_json`, `mcp_fail --type`), and `server.meta.json` records the mcp-bash API version. Also from 1.7–1.9: resource reads time out after 120 seconds, a request that times out gets an error response, and a failed write to the client stops the server.
- **Read-only mode uses mcp-bash's restrict-only policy hook**: `server.d/policy.sh` defines `mcp_tools_policy_project`, which runs after the framework's allowlist and path checks and can only narrow them.
- **The Docker image uses mcp-bash 1.9.0**, installed from the verified release tarball, instead of 0.9.6.

### Fixed

- **`GIT_HEX_DEBUG`, `GIT_HEX_DEBUG_SPLIT` and `GIT_HEX_DEBUG_REBASE` reach the tools**: the tool env allowlist was in `server.d/env.sh`, which the server never loads, so tools never received them. It is now in `server.meta.json`.
- **`./git-hex.sh run-tool` works**: the launcher sent it to the vendored runtime, which has no CLI commands. It now runs the system `mcp-bash` (1.8 or later; older versions are refused, since they don't enforce read-only mode), with git-hex's tool allowlist.
- **`rebaseWithPlan` works with jq 1.6** (Debian 12, Ubuntu 22.04): every plan was rejected with "Commit message cannot contain null bytes", because jq 1.6's `contains("\u0000")` is true for any string.
- **`splitCommit` no longer needs an executable temp directory**: its sequence-editor script is run through `bash`, so it works where `TMPDIR` is mounted `noexec`.
- **`checkRebaseConflicts` requires Git 2.40, and says so**: it uses `git merge-tree --merge-base`, added in Git 2.40, but accepted Git 2.38 and 2.39 (Debian 12 ships 2.39). There every prediction failed, and the tool reported a conflict for every rebase. It now refuses older Git with `GIT_VERSION_UNSUPPORTED`.
- **Error suggestions are complete with jq 1.6**: the last suggestion was dropped.
- **`docker build` works again**: the build step used `set -o pipefail`, which Debian's `/bin/sh` rejects.
- **Docs no longer describe `./git-hex.sh install`, `mcp-bash.lock` or `GIT_HEX_MCPBASH_SHA256`**, which went away when the runtime was vendored. CONTRIBUTING shows the current result and error helpers.

### Known issues

- **A tool that times out returns an error whose `structuredContent` is `{"success": false, "error": {...}}`**, which doesn't match the tool's `outputSchema`. This comes from mcp-bash and will be fixed there; strict clients may reject that one result. All other errors carry their details in `_meta["mcpbash/error"]` only.

## [0.3.0] - 2026-10-10

0.2.0 was never tagged or published, so this is the first release after 0.1.0 and also includes the 0.2.0 changes below.

### Security

- **The tool allowlist is enforced again**: `server.d/policy.sh` replaced the framework's default tool policy without calling it, so `MCPBASH_TOOL_ALLOWLIST` was never checked and every tool could run regardless of it. The policy now runs the framework's default check first, then git-hex's read-only rules. `policy.sh` also no longer runs `set -euo pipefail` at the top level, which changed the server's own shell options when the file was sourced.

  **Check your client config if you upgrade.** Configs that start git-hex through `git-hex.sh`, `git-hex-env.sh` or the Docker image need no change: those set the allowlist. MCPB bundles set `*`. A config that starts `mcp-bash` or `.mcp-bash/bin/mcp-bash` directly must now set the allowlist, or every tool call is refused:

  ```json
  "MCPBASH_TOOL_ALLOWLIST": "git-hex-getRebasePlan git-hex-checkRebaseConflicts git-hex-getConflictStatus git-hex-rebaseWithPlan git-hex-splitCommit git-hex-createFixup git-hex-amendLastCommit git-hex-cherryPickSingle git-hex-resolveConflict git-hex-continueOperation git-hex-abortOperation git-hex-undoLast"
  ```

  If you set `MCPBASH_TOOL_ALLOWLIST` yourself to a narrower list, that list now takes effect.

### Changed

- **Vendored mcp-bash runtime upgraded from 1.2.2 to 1.6.0** (from the verified v1.6.0 release tarball). Notable for git-hex users: tools and providers get only framework-owned `MCP_*` variables; a declared resource `mimeType` is reported as declared (git-hex's templates declare `text/plain`); runtime state directories get random names; HTTPS/git providers check addresses more strictly. See the [mcp-bash CHANGELOG](https://github.com/yaniv-golan/mcp-bash-framework/blob/main/CHANGELOG.md) (1.3.0 to 1.6.0) for details.

## [0.2.0] - 2026-04-05

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

### Improved

- **Skills rewritten** for better triggering accuracy and tool guidance:
  - `git-hex-branch-cleanup` — tool selection table, stash restore failure handling, expanded gotchas (reword requires message, single-line messages, staged changes for fixup)
  - `git-hex-conflict-resolution` — `includeContent` usage guidance, conflict marker removal warnings, `continueOperation` re-pause handling, revert/bisect limitations
  - `git-hex-pr-workflow` — PR description from commit history, review feedback fixup workflow, stacked PR support, fetch-before-rebase pattern
  - All descriptions optimized with explicit negative triggers to prevent cross-skill misfiring

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

[Unreleased]: https://github.com/yaniv-golan/git-hex/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/yaniv-golan/git-hex/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/yaniv-golan/git-hex/compare/v0.1.0...v0.3.0
[0.2.0]: https://github.com/yaniv-golan/git-hex/blob/v0.3.0/CHANGELOG.md#020---2026-04-05
[0.1.0]: https://github.com/yaniv-golan/git-hex/releases/tag/v0.1.0
