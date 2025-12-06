---
name: git-hex-conflict-resolution
description: >
  Inspect and resolve git-hex rebase/merge/cherry-pick conflicts. Use this Skill
  when a git operation is paused due to conflicts and the user wants the agent
  to resolve and continue or abort safely.
---

# Git-hex Conflict Resolution

## When to use this Skill

Use this Skill when:

- A git-hex tool reports that an operation is paused because of conflicts.
- The user says a rebase or cherry-pick is "stuck", "paused", or "in conflict".
- You need to see which files conflict and decide whether to continue or abort.

## Workflow

1. **Inspect conflict state**
   - Call `gitHex.getConflictStatus` to determine:
     - Whether a rebase/merge/cherry-pick is in progress.
     - Which files are conflicting and the overall operation type (`rebase`,
       `merge`, or `cherry-pick`).
   - Use `includeContent: true` only when necessary to inspect base/ours/theirs
     content for specific text files.

2. **Resolve conflicts per file**
   - For text files:
     - Propose or apply edits based on `base`, `ours`, and `theirs`.
     - Ensure conflict markers are removed before resolving.
     - Call `gitHex.resolveConflict` with the file path (and `resolution: "delete"`
       for delete conflicts when appropriate).
   - For delete/rename conflicts, use the `resolution` parameter to choose whether
     to keep or remove the file.

3. **Continue or abort the operation**
   - When all conflicts are resolved (or `getConflictStatus` shows no remaining
     conflicting files but the operation is still paused), call `gitHex.continueOperation`.
   - If the user decides to give up on the rebase or cherry-pick, call
     `gitHex.abortOperation` to restore the pre-operation state.

4. **Escalate if needed**
   - If the final result after continuing is not what the user wanted, suggest
     using `gitHex.undoLast` from the branch cleanup Skill to revert.

## Tools to prefer

- Inspection: `gitHex.getConflictStatus`
- Resolution: `gitHex.resolveConflict`
- Control: `gitHex.continueOperation`, `gitHex.abortOperation`
- Recovery: `gitHex.undoLast` (via the branch cleanup Skill)

## Conflict types

### Operation-level
- `"rebase"` - Interactive rebase paused
- `"merge"` - Merge in progress
- `"cherry-pick"` - Cherry-pick paused

### File-level
- `"both_modified"` - Both sides modified the file
- `"deleted_by_us"` - We deleted, they modified
- `"deleted_by_them"` - We modified, they deleted
- `"added_by_both"` - Both sides added different versions

## Delete conflict handling

```json
// To keep the file (must exist on disk):
{ "file": "path/to/file", "resolution": "keep" }

// To accept deletion:
{ "file": "path/to/file", "resolution": "delete" }
```
