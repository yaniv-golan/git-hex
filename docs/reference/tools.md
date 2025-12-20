# Tool reference

This is the per-tool API reference.

## Tools

### git-hex-getRebasePlan

Get a structured view of recent commits for rebase planning and inspection.

> **Note:** The `count` parameter limits how many commits are returned. When `onto` is not specified, the tool uses the upstream tracking branch if available, otherwise defaults to `HEAD~count`. This means `count` affects both the display limit *and* the default commit range. To inspect a specific range, always provide an explicit `onto` value.
> For single-commit repositories, the default base is the empty tree so the lone commit is included. To avoid surprises when a branch has an upstream, set both `onto` (e.g., `main`) and `count` (for display only).

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

### git-hex-rebaseWithPlan

Structured interactive rebase with plan support (reorder, drop, squash, reword) plus conflict pause/resume.

> **Prerequisites:** Working tree must be clean unless `autoStash=true`. All history-mutating operations create a backup ref for `undoLast`.

> **Notes:**
> - Rebases the range `onto..HEAD`
> - `plan` controls actions per commit; partial plans default missing commits to `pick`
> - `abortOnConflict=false` leaves the rebase paused so you can call `getConflictStatus` / `resolveConflict` / `continueOperation`
> - Uses native `--autostash` when `autoStash=true`

The rebase can also pause for non-conflict reasons (e.g., a git hook rejecting a rewritten commit). In that case `paused=true`, `reason="stopped"`, and `conflictingFiles` is empty; you can inspect the repo state and then call `continueOperation` or `abortOperation`.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `onto` | string | **Yes** | Base ref to rebase onto |
| `plan` | array | No | Ordered list of `{action, commit, message?}` items (action: pick, reword, squash, fixup, drop) |
| `abortOnConflict` | boolean | No | Abort on conflicts (default: true). Set to false to pause and resolve instead of auto-aborting. |
| `autoStash` | boolean | No | Use native `--autostash` to stash/restore tracked changes (default: false) |
| `autosquash` | boolean | No | Auto-squash fixup! commits (default: true) |
| `requireComplete` | boolean | No | If true, plan must list all commits (enables reordering) |
| `signCommits` | boolean | No | If true, allow commit signing during the rebase. Default false to avoid non-interactive pinentry hangs. |

**Example:**
```json
{
  "onto": "main",
  "autosquash": true,
  "plan": [
    { "action": "pick", "commit": "abc123" },
    { "action": "drop", "commit": "def456" }
  ]
}
```

**Returns:**
```json
{
  "success": true,
  "paused": false,
  "headBefore": "abc123...",
  "headAfter": "def456...",
  "backupRef": "git-hex/backup/1700000000_rebaseWithPlan_xxx",
  "summary": "Rebased 5 commits onto main",
  "commitsRebased": 5
}
```

**When paused on conflict (`abortOnConflict=false`):**
```json
{
  "success": false,
  "paused": true,
  "reason": "conflict",
  "headBefore": "abc123...",
  "headAfter": "def456...",
  "backupRef": "git-hex/backup/1700000000_rebaseWithPlan_xxx",
  "conflictingFiles": ["src/file.ts"],
  "summary": "Rebase paused due to conflicts. Use getConflictStatus for details."
}
```

**When paused for a non-conflict stop:**
```json
{
  "success": false,
  "paused": true,
  "reason": "stopped",
  "headBefore": "abc123...",
  "headAfter": "def456...",
  "backupRef": "git-hex/backup/1700000000_rebaseWithPlan_xxx",
  "conflictingFiles": [],
  "summary": "Rebase paused (non-conflict stop): <details>."
}
```

### git-hex-checkRebaseConflicts

Dry-run a rebase using `git merge-tree` (Git 2.38+) without touching the worktree. Returns per-commit predictions (`clean`, `conflict`, `unknown` after the first conflict), `limitExceeded`, and a summary.

> **Git version:** Requires Git 2.38+ (uses `merge-tree --write-tree` internally, isolated in a temp object directory to avoid touching repo objects).

Key inputs: `onto` (required), `maxCommits` (default 100). Outputs are estimates only; run `getConflictStatus` after an actual pause to see real conflicts.

`confidence` is `"estimate"` when predictions were computed normally; it is `"unknown"` when `merge-tree` errors for a commit, in which case the tool fails safe by reporting `wouldConflict=true`.
Merge commits are ignored (matching the default behavior of `git rebase` without `--rebase-merges`).

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `onto` | string | **Yes** | Base ref to rebase onto |
| `maxCommits` | integer | No | Maximum commits to check (default: 100) |

**Example output:**
```json
{
  "success": true,
  "wouldConflict": true,
  "confidence": "estimate",
  "commits": [
    { "hash": "8b3f1c2", "subject": "Clean change", "prediction": "clean" },
    { "hash": "a1b2c3d", "subject": "Conflicting change", "prediction": "conflict" },
    { "hash": "c4d5e6f", "subject": "After conflict", "prediction": "unknown" }
  ],
  "limitExceeded": false,
  "totalCommits": 3,
  "checkedCommits": 3,
  "summary": "Rebase would conflict at commit 2/3 (a1b2c3d)",
  "note": "Predictions may not match actual rebase behavior in all cases"
}
```

### Conflict Workflow

- **git-hex-getConflictStatus** — Detects whether a rebase/merge/cherry-pick/revert is paused, which files conflict, and optional base/ours/theirs content (`includeContent`, `maxContentSize`).
- **git-hex-resolveConflict** — Marks a file as resolved (`resolution`: `keep` or `delete`, handles delete conflicts and paths with spaces).
- **git-hex-continueOperation** — Runs `rebase --continue`, `cherry-pick --continue`, or `merge --continue`, returning `completed`/`paused` with conflicting files when paused.
- **git-hex-abortOperation** — Aborts the in-progress rebase/merge/cherry-pick and restores the original state.

### git-hex-getConflictStatus

Detect whether a rebase/merge/cherry-pick/revert is paused, which files conflict, and (optionally) return per-file content.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `includeContent` | boolean | No | Include base/ours/theirs/workingCopy content for each conflict (default: false) |
| `maxContentSize` | integer | No | Maximum bytes of content to return per file (default: 10000) |

**File `conflictType` values:** `both_modified`, `deleted_by_us`, `deleted_by_them`, `added_by_both`, `deleted_by_both`, `unknown`.

When `includeContent=true`, each file may include `base`, `ours`, `theirs`, and `workingCopy` (text files), plus `isBinary`, optional `note`, and `truncated` when any returned content was clipped to `maxContentSize`.

**Returns:**
```json
{
  "success": true,
  "inConflict": true,
  "conflictType": "rebase",
  "currentStep": 1,
  "totalSteps": 3,
  "conflictingCommit": "abc123...",
  "conflictingFiles": [
    {
      "path": "conflict.txt",
      "conflictType": "both_modified"
    }
  ],
  "summary": "Rebase paused with conflicts"
}
```

When `inConflict=false`, `conflictType` is `"none"`.

**Example (`includeContent=true`):**
```json
{
  "success": true,
  "inConflict": true,
  "conflictType": "rebase",
  "currentStep": 1,
  "totalSteps": 3,
  "conflictingCommit": "abc123...",
  "conflictingFiles": [
    {
      "path": "conflict.txt",
      "conflictType": "both_modified",
      "isBinary": false,
      "truncated": false,
      "base": "base content...",
      "ours": "ours content...",
      "theirs": "theirs content...",
      "workingCopy": "working tree content..."
    }
  ],
  "summary": "Rebase paused with conflicts"
}
```

### git-hex-resolveConflict

Mark a conflicted file as resolved by either keeping the file (after you resolved conflict markers) or deleting it.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `file` | string | **Yes** | Repo-relative path to the conflicted file (no absolute paths, traversal segments, drive letters, or null bytes) |
| `resolution` | string | No | `keep` (default) or `delete` |

**Returns:**
```json
{
  "success": true,
  "file": "conflict.txt",
  "remainingConflicts": 0,
  "summary": "Marked conflict.txt as resolved. 0 conflict(s) remaining."
}
```

### git-hex-continueOperation

Continue a paused rebase/merge/cherry-pick after resolving conflicts.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |

**Returns:**
```json
{
  "success": true,
  "operationType": "rebase",
  "completed": true,
  "paused": false,
  "conflictingFiles": [],
  "summary": "Rebase completed successfully"
}
```

On failure, `success` is false and an `error` string may be included.

**Example (failure with error):**
```json
{
  "success": false,
  "operationType": "rebase",
  "completed": false,
  "paused": false,
  "conflictingFiles": [],
  "error": "Failed to continue rebase (no conflicts detected). <details>",
  "summary": "Failed to continue rebase (no conflicts detected). <details>"
}
```

### git-hex-abortOperation

Abort a paused rebase/merge/cherry-pick and restore the original state.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |

**Returns:**
```json
{
  "success": true,
  "operationType": "rebase",
  "summary": "rebase aborted, restored to original state"
}
```

If nothing is in progress, `operationType` is `"none"` and `success` is false.

On failure, `success` is false and an `error` string may be included.

**Example (failure with error):**
```json
{
  "success": false,
  "operationType": "rebase",
  "error": "Failed to abort rebase: <details>",
  "summary": "Failed to abort rebase"
}
```

### git-hex-splitCommit

Split a commit into multiple commits by file (file-level only; no hunk splitting). Validates coverage of all files, rejects merge/root commits, and supports `autoStash`. Returns new commit hashes, `backupRef`, `rebasePaused` (if a later commit conflicts), and `stashNotRestored` when a pop fails.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository (defaults to single root) |
| `commit` | string | **Yes** | Commit hash/ref to split (must be ancestor of HEAD, non-merge, non-root) |
| `splits` | array | **Yes** | Array of `{ files: [...], message: "<single-line>" }` (min 2) |
| `autoStash` | boolean | No | Automatically stash/restore uncommitted changes (default: false) |
| `signCommits` | boolean | No | If true, allow commit signing. Default false to avoid non-interactive pinentry hangs. |

**Returns:**
```json
{
  "success": true,
  "originalCommit": "abc123...",
  "newCommits": [
    { "hash": "def456...", "message": "Split part 1", "files": ["file1.txt"] },
    { "hash": "789abcd...", "message": "Split part 2", "files": ["file2.txt"] }
  ],
  "backupRef": "git-hex/backup/1700000000_splitCommit_xxx",
  "rebasePaused": false,
  "stashNotRestored": false,
  "summary": "Split abc1234 into 2 commits"
}
```

### git-hex-createFixup

Create a fixup commit targeting a specific commit.

> **Prerequisites:** Changes must be staged (`git add`) before running. This tool commits the currently staged changes as a fixup.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `commit` | string | **Yes** | Commit hash/ref to create fixup for |
| `message` | string | No | Additional message to append |
| `signCommits` | boolean | No | If true, allow commit signing. Default false to avoid non-interactive pinentry hangs. |

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
  "backupRef": "git-hex/backup/1700000000_createFixup_xxx",
  "targetCommit": "abc123...",
  "summary": "Created fixup commit ghi789 targeting abc123",
  "commitMessage": "fixup! Original commit message"
}
```

### git-hex-amendLastCommit

Amend the last commit with staged changes and/or a new message.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `message` | string | No | New commit message |
| `addAll` | boolean | No | Stage all tracked modified files (default: false) |
| `autoStash` | boolean | No | Automatically stash unstaged changes before amending (default: false) |
| `signCommits` | boolean | No | If true, allow commit signing. Default false to avoid non-interactive pinentry hangs. |

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
  "backupRef": "git-hex/backup/1700000000_amendLastCommit_xxx",
  "summary": "Amended commit with new hash jkl012",
  "commitMessage": "Updated commit message",
  "stashNotRestored": false
}
```

### git-hex-cherryPickSingle

Cherry-pick a single commit with configurable merge strategy.

> **Prerequisites:** Working tree must be clean (no uncommitted changes) unless `autoStash=true`, which stashes/restore tracked changes automatically. Commit or stash changes before running otherwise.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `commit` | string | **Yes** | Commit hash/ref to cherry-pick |
| `strategy` | string | No | Merge strategy: recursive, ort, resolve |
| `noCommit` | boolean | No | Apply without committing (default: false) |
| `abortOnConflict` | boolean | No | If false, pause on conflicts instead of aborting (default: true) |
| `autoStash` | boolean | No | Automatically stash/restore tracked changes (requires `abortOnConflict=true`, default: false) |
| `signCommits` | boolean | No | If true, allow commit signing. Default false to avoid non-interactive pinentry hangs. |

**Example:**
```json
{
  "commit": "abc123",
  "strategy": "ort",
  "abortOnConflict": true,
  "autoStash": true
}
```

**Returns:**
```json
{
  "success": true,
  "headBefore": "def456...",
  "headAfter": "mno345...",
  "backupRef": "git-hex/backup/1700000000_cherryPickSingle_xxx",
  "sourceCommit": "abc123...",
  "summary": "Cherry-picked abc123 as new commit mno345",
  "commitMessage": "Original commit subject line",
  "stashNotRestored": false
}
```

**Example (paused on conflict, `abortOnConflict=false`):**
```json
{
  "success": false,
  "paused": true,
  "reason": "conflict",
  "headBefore": "def456...",
  "headAfter": "def456...",
  "backupRef": "git-hex/backup/1700000000_cherryPickSingle_xxx",
  "sourceCommit": "abc123...",
  "commitMessage": "Original commit subject line",
  "conflictingFiles": ["conflict.txt"],
  "stashNotRestored": false,
  "summary": "Cherry-pick paused due to conflicts. Use getConflictStatus and resolveConflict to continue."
}
```

### git-hex-undoLast

Undo the last git-hex operation by resetting to the backup ref.

> **Prerequisites:** Working tree must be clean (no uncommitted changes). Commit or stash changes before running.

Every history-mutating git-hex operation (amend, fixup, rebase, split, cherry-pick) automatically creates a backup ref before making changes. This tool restores the repository to that state.

> **Safety note:** By default, `undoLast` refuses to run if the reset would overwrite an untracked file (e.g., you created an untracked file at a path that was tracked in the backup state). Re-run with `force=true` only if you are OK losing those untracked changes.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repoPath` | string | No | Path to git repository |
| `force` | boolean | No | Allow undo even if new commits exist after the backup (those commits will be lost), and allow overwriting untracked files that collide with tracked paths in the backup state |

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

`undoneOperation` may be `"unknown"` when git-hex cannot determine the originating operation for an older backup.

> **Note:** On the success no-op path (“already at backup state”), `backupRef` and `commitsUndone` are not returned.
