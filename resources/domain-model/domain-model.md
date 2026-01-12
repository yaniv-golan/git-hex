# git-hex Domain Model

## Core Concepts

### Rebase Plan
A rebase plan is a preview of commits that will be replayed during an interactive rebase. Use `getRebasePlan` to see the commits in a range before calling `rebaseWithPlan`. The plan shows commit hashes, subjects, authors, and dates in rebase order (oldest first).

### Backup Refs
Every history-mutating operation creates a backup ref at `refs/git-hex/backup/<operation-name>`. This allows recovery via `undoLast` if something goes wrong. Backups are created before the operation starts and persist until overwritten by the next operation of the same type.

### Operation States
- **clean**: No git operation in progress - safe to perform any operation
- **rebase**: Mid-rebase (conflicts or paused at edit step)
- **cherry-pick**: Mid-cherry-pick with conflicts
- **merge**: Mid-merge with conflicts
- **bisect**: Git bisect in progress

Most git-hex tools require a clean state. Use `getConflictStatus` to check current state.

## Tool Categories

### Read-Only Tools (Safe)
- **getRebasePlan**: Preview commits for rebasing. Use BEFORE rebaseWithPlan to understand what will be rebased.
- **checkRebaseConflicts**: Simulate rebase to predict conflicts. Use when unsure if rebase will succeed.
- **getConflictStatus**: Check current conflict state. Use when an operation paused or to verify clean state.

### History-Mutating Tools (Create Backups)
- **rebaseWithPlan**: Execute an interactive rebase with actions (pick, squash, fixup, drop, reword). Always creates backup.
- **splitCommit**: Split a commit into multiple commits by file. Each file from original goes to exactly one new commit.
- **createFixup**: Create a `fixup!` commit targeting an older commit. Use with rebaseWithPlan autosquash=true.
- **amendLastCommit**: Amend HEAD with staged changes. Only works on unpushed commits.
- **cherryPickSingle**: Cherry-pick one commit. For ranges, use rebaseWithPlan instead.

### Conflict Resolution
- **resolveConflict**: Mark a file as resolved after manually fixing conflicts.
- **continueOperation**: Continue a paused rebase/cherry-pick/merge.
- **abortOperation**: Abort and restore to pre-operation state.

### Recovery
- **undoLast**: Restore from the most recent backup ref. Only works if no new commits were added after the backup.

## Common Workflows

### Clean Up Feature Branch Before Merge
1. `getRebasePlan` to see commits
2. `checkRebaseConflicts` if rebasing onto updated main
3. `rebaseWithPlan` with squash/fixup actions to combine related commits

### Fix Typo in Old Commit
1. Make the fix and stage it
2. `createFixup` targeting the commit with the typo
3. `rebaseWithPlan` with autosquash=true

### Split Overly Large Commit
1. `splitCommit` with files grouped by logical change
2. Each group becomes a new commit with its own message

### Handle Conflicts During Rebase
1. `getConflictStatus` to see conflicting files
2. Edit files to resolve conflicts
3. `resolveConflict` for each resolved file
4. `continueOperation` to proceed

### Recover from Mistake
1. `undoLast` immediately after the problematic operation
2. The backup ref restores HEAD to pre-operation state

## Safety Notes

- All mutating operations create backup refs before making changes
- Use `getRebasePlan` and `checkRebaseConflicts` before destructive operations
- Never use mutating tools on shared/pushed branches without coordination
- `undoLast` only works immediately after an operation (before new commits)
