# git-hex Server Instructions

You are connected to git-hex, an MCP server for safe, non-interactive git history refactoring.

## Safety Rules

1. **Always inspect before mutating.** Call `getRebasePlan` before `rebaseWithPlan` to understand the current commit history and what will change.
2. **Check for in-progress operations first.** Before calling any mutating tool, verify no rebase/merge/cherry-pick is already in progress by calling `getConflictStatus`. Mutating tools will reject the call if an operation is active, but checking first gives you better context.
3. **Read-only tools are safe to call anytime:** `getRebasePlan`, `checkRebaseConflicts`, `getConflictStatus`.
4. **Mutating operations create backup refs** so `undoLast` can reverse them. Always mention `undoLast` to the user as a safety net when performing destructive operations.

## Recommended Workflows

### Fixup a past commit
1. `getRebasePlan` — identify the target commit to fix
2. User stages the fix (`git add`)
3. `createFixup` with the target commit SHA — creates a `fixup!` commit
4. `rebaseWithPlan` with auto-squash — squashes the fixup into the target

### Split a commit by files
1. `getRebasePlan` — identify the commit to split
2. `splitCommit` with the commit SHA and file groups — splits into multiple commits

### Amend the last commit
1. User stages changes (`git add`)
2. `amendLastCommit` — amends HEAD with staged changes

### Cherry-pick a single commit
1. `cherryPickSingle` with the source commit SHA
2. If conflicts arise, follow the conflict resolution workflow below

### Resolve conflicts (during paused rebase or cherry-pick)
1. `getConflictStatus` — see which files conflict and what operation is paused
2. `resolveConflict` for each conflicting file — resolve with ours/theirs/manual content
3. `continueOperation` — resume the paused rebase/cherry-pick

### Abort a paused operation
1. `abortOperation` — cleanly abort and restore pre-operation state

### Undo the last mutating operation
1. `undoLast` — reverts the most recent amend/fixup/cherry-pick/rebase/split using the backup ref

## Tool Selection Guide

| Goal | Tool | Notes |
|------|------|-------|
| Fix something in the last commit | `amendLastCommit` | Only works on HEAD |
| Fix something in an older commit | `createFixup` + `rebaseWithPlan` | Works on any ancestor |
| Reorder, squash, or drop commits | `rebaseWithPlan` | Use `getRebasePlan` first to build the plan |
| Bring a commit from another branch | `cherryPickSingle` | Single commit only |
| Split a commit into smaller ones | `splitCommit` | Splits by file groups |
| Check if a rebase will have conflicts | `checkRebaseConflicts` | Dry-run conflict prediction |
| See current conflict state | `getConflictStatus` | Shows conflicting files and operation type |
| Resume after resolving conflicts | `continueOperation` | After all conflicts resolved |
| Cancel an in-progress operation | `abortOperation` | Restores pre-operation state |
| Reverse the last operation | `undoLast` | Uses backup refs; not safe if new commits added after (use `force`) |

## Common Pitfalls

- **Don't rebase with conflicts present.** Resolve or abort the current operation first.
- **Don't forget `continueOperation`.** After resolving all conflicts with `resolveConflict`, you must call `continueOperation` to finish the paused rebase/cherry-pick.
- **Verify after mutations.** Call `getRebasePlan` after any mutating operation to confirm the history looks as expected.
- **`undoLast` has limits.** It is not safe if new commits were added after the backup ref was created. Use the `force` parameter to override, but warn the user about potential data loss.
- **`checkRebaseConflicts` is predictive, not definitive.** It tests each commit individually against the base. Cascading conflicts (where resolving one conflict changes the context for the next) may not be detected.
