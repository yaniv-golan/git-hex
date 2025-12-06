---
name: git-hex-branch-cleanup
description: >
  Clean up a feature branch's history using git-hex. Use this Skill when the user
  wants to rewrite or polish their git history (squash/fixup commits, reorder,
  drop, split commits, or rebase a branch onto main) without using an interactive
  terminal.
---

# Git-hex Branch Cleanup

## When to use this Skill

Use this Skill when:

- The user says they want to "clean up", "rewrite", "polish", or "squash" a git
  history or feature branch.
- The user wants to rebase a branch onto another branch (e.g. `main`) and present
  a clean, reviewable set of commits.
- The user wants to split, squash, or reword commits using git-hex tools instead
  of manual interactive rebase.

## Workflow

1. **Plan first**
   - Call `gitHex.getRebasePlan` to inspect the commit range you would modify.
   - Optionally call `gitHex.checkRebaseConflicts` to estimate whether the rebase
     is likely to conflict.

2. **Prepare changes**
   - For small edits to the last commit, prefer `gitHex.amendLastCommit`.
   - For fixes to older commits, guide the user to edit and stage changes, then
     use `gitHex.createFixup` targeting the original commit.
   - For large or mixed commits, consider `gitHex.splitCommit` to separate files
     into focused commits.

3. **Apply the rewrite**
   - Use `gitHex.rebaseWithPlan` to reorder, drop, squash, or reword commits.
   - Prefer `autoStash: true` and `autosquash: true` when the working tree is dirty,
     following git-hex documentation.
   - Never use git-hex on shared or protected branches; operate on feature branches
     the user controls.

4. **Safety and recovery**
   - If the result is not what the user wanted, call `gitHex.undoLast` to restore
     the previous state using git-hex backup refs.
   - If a rebase pauses with conflicts, hand off to the conflict resolution Skill.

## Tools to prefer

- Planning: `gitHex.getRebasePlan`, `gitHex.checkRebaseConflicts`
- History rewrite: `gitHex.rebaseWithPlan`, `gitHex.createFixup`,
  `gitHex.amendLastCommit`, `gitHex.splitCommit`, `gitHex.cherryPickSingle`
- Recovery: `gitHex.undoLast`

## Key constraints

- `reword` action **requires** `message` field (without it, git opens an editor → hang).
- Messages must be **single-line** (no TAB/newline characters).
- For reordering commits, set `requireComplete: true` in the plan.
- Prefer `fixup` over `squash` unless you need to combine commit messages.
- Check `stashNotRestored: true` in output - means user needs `git stash pop`.
