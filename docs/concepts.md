# Concepts

This page defines a few terms used across git-hex docs and error messages.

## Allowed folders (MCP `roots`)

Your MCP client must specify which directories the server is allowed to access. These are commonly called MCP `roots` (some clients use names like `allowedRoots`).

Why this matters:
- If the repo you want to work on is not under an allowed folder, the server will refuse to read/write it.
- This is a safety feature: it limits filesystem access to explicit directories you choose.

Example:
- Allowed folder: `/Users/me/code`
- Allowed repos: `/Users/me/code/my-repo`, `/Users/me/code/other-repo`
- Disallowed: `/Users/me/Desktop/some-repo` (outside the allowed folder)

## `repoPath`

Many git-hex tools accept `repoPath`, the path to the Git repository to operate on.

Why this matters:
- With a single allowed folder configured, some tools/clients can default `repoPath` to that root.
- With multiple allowed folders, you typically must pass `repoPath` explicitly so the server can choose the correct repository.

## Operation state (rebase/merge/cherry-pick in progress)

Git can be “mid-operation” (e.g., an interactive rebase is paused, a cherry-pick is conflicted). Tools may refuse to start a new operation if one is already in progress.

Why this matters:
- Starting a second history-rewrite while one is paused can corrupt state or make recovery harder.
- git-hex’s conflict helpers exist specifically to inspect/continue/abort safely.

## Read-only mode (`GIT_HEX_READ_ONLY=1`)

Setting `GIT_HEX_READ_ONLY=1` blocks all mutating tools.

Why this matters:
- Useful for inspection-only environments.
- Helps enforce “no history changes” policies.

## Backup refs (`refs/git-hex/backup/...`)

Before mutating history, git-hex creates backup refs under `refs/git-hex/backup/...` (and updates `refs/git-hex/last/...`).

Why this matters:
- Provides a reliable recovery point for `undoLast` and manual `git reset --hard <backup-ref>` workflows.
- Makes history rewrites safer and more auditable.

