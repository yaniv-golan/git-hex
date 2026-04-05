---
name: git-hex-conflict-resolution
description: >
  Use whenever a git operation is mid-flight and needs help finishing. Triggers:
  "continue the rebase", "abort the rebase", "conflicts in files", "rebase
  stopped/stuck/paused", "cherry-pick conflict", "revert has conflicts", "merge
  conflict", git status showing unmerged paths, or any git-hex tool returning
  paused/conflict/conflictingFiles status. Helps resolve conflicting files one
  by one, then continue or abort the operation. Applies to rebase, merge,
  cherry-pick, and revert — but only when already in progress. NOT for starting
  new rebases, creating PRs, squashing, fixup commits, undoing completed
  operations, or git-hex setup.
---

# Git-hex Conflict Resolution

Use this skill when a git-hex operation is paused due to conflicts — or when
the user reports being stuck in a rebase, merge, cherry-pick, or revert.

## Workflow

### 1. Inspect the conflict state

Call `git-hex-getConflictStatus` to determine:
- Whether an operation is in progress and what type (`rebase`, `merge`,
  `cherry-pick`, `revert`)
- Which files are conflicting and the conflict type per file
- For rebases: `currentStep` / `totalSteps` progress

**When to use `includeContent: true`:**
- When you need to see the actual base/ours/theirs content to propose a
  resolution — typically for text files where you'll edit and resolve.
- Skip it for binary files (they'll be flagged `isBinary: true`) or when
  you just need to see the list of conflicting files.
- Use `maxContentSize` (default 10000) to limit large files. Content is
  truncated per-file and marked with `truncated: true`.

**Important:** `inConflict: true` can persist even after all files are resolved
if the operation is still paused. Check `conflictingFiles` length, not just
`inConflict`.

### 2. Resolve each conflicting file

**For text files (`both_modified`, `added_by_both`):**
1. Read the conflict content (base/ours/theirs) from the `getConflictStatus`
   response or by reading the file directly.
2. Edit the file to produce the correct merged content. **Remove all conflict
   markers** — `resolveConflict` with `resolution: "keep"` will reject the file
   if any `<<<<<<<`, `=======`, `>>>>>>>`, or `|||||||` markers remain.
3. Call `git-hex-resolveConflict` with `file` and `resolution: "keep"`.

**For delete conflicts (`deleted_by_us`, `deleted_by_them`):**
- `resolution: "keep"` — restores the file (from theirs if deleted_by_us,
  from ours if deleted_by_them).
- `resolution: "delete"` — accepts the deletion.
- Ask the user which they prefer if the intent isn't clear.

**Path rules:** The `file` parameter must be a POSIX repo-relative path. No
absolute paths, no `../` traversal, no drive letters.

After each resolution, `resolveConflict` returns `remainingConflicts` — the
count of files still in conflict.

### 3. Continue or abort

**Continue** — when all conflicts are resolved (`remainingConflicts: 0`) or
`getConflictStatus` shows no remaining conflicting files:
- Call `git-hex-continueOperation`.
- It may return `paused: true` again if the next commit in a rebase also
  conflicts. Go back to step 1 in that case.
- Supports: rebase, cherry-pick, merge. Does **not** support revert or bisect —
  for those, suggest `git revert --continue` / `git bisect reset` directly.

**Abort** — if the user wants to abandon the operation:
- Call `git-hex-abortOperation`. This restores the pre-operation state.
- For a rebase initiated by git-hex, `git-hex-undoLast` is also available
  as recovery after the operation completes (if the result wasn't what the
  user wanted).

### 4. Verify the result

After `continueOperation` reports `completed: true`, confirm the state:
- Use `git-hex-getRebasePlan` or `git log` to show the user the final history.
- If the result isn't right, suggest `git-hex-undoLast` to roll back.

## Conflict types reference

### Operation-level
| Type | Meaning |
|------|---------|
| `rebase` | Interactive rebase paused mid-apply |
| `merge` | Merge in progress |
| `cherry-pick` | Cherry-pick paused |
| `revert` | Revert paused (limited tool support — see above) |

### File-level
| Type | Meaning | Typical resolution |
|------|---------|-------------------|
| `both_modified` | Both sides changed the file | Edit to merge, then keep |
| `deleted_by_us` | We deleted, they modified | keep (restore) or delete |
| `deleted_by_them` | We modified, they deleted | keep (restore) or delete |
| `added_by_both` | Both sides added different versions | Edit to merge, then keep |
