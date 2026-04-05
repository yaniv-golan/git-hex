---
name: git-hex-branch-cleanup
description: >
  Rewrite git branch history. Invoke for any commit manipulation: squash,
  reword, reorder, drop, split, fold fixups, amend, or rebase onto main.
  Handles "clean up my commits", "squash before PR", "fix commit message typo",
  "make branch reviewable", "fold in fixup commits", "drop a commit", "rebase
  my branch". Operates on existing commits using git-hex MCP tools — no
  interactive rebase needed. NOT for: merge conflicts, cherry-picks across
  branches, conflict checking, git concepts, or hooks setup.
---

# Git-hex Branch Cleanup

Use this skill when the user wants to reshape a feature branch's commit history
using git-hex tools instead of manual interactive rebase.

## Workflow

### 1. Assess the situation

- Call `git-hex-getRebasePlan` to see the commit range.
  - Use `count` to control how far back (default 10, max 200).
  - Commits come back oldest-first — the natural order for a rebase plan.
  - If `onto` is omitted it defaults to `@{upstream}` or `HEAD~count`.
- Optionally call `git-hex-checkRebaseConflicts` to predict conflicts before
  starting. This requires **git 2.38+** — if the user's git is older, skip it
  and note the limitation.

### 2. Choose the right tool for the job

| Goal | Tool | Notes |
|------|------|-------|
| Edit the last commit (message or content) | `amendLastCommit` | Use `addAll: true` to stage tracked changes automatically. Needs at least staged changes OR a new `message`. |
| Fix an older commit | `createFixup` → `rebaseWithPlan` | User must stage changes first. Then `createFixup` targets the commit; follow with `rebaseWithPlan` using `autosquash: true` to fold it in. |
| Reorder, drop, squash, or reword | `rebaseWithPlan` | Pass a `plan` array. For reordering, set `requireComplete: true`. |
| Break a commit into focused pieces | `splitCommit` | Requires `splits` array with ≥2 entries. Every file in the original commit must appear in exactly one split. |
| Cherry-pick a single commit | `cherryPickSingle` | Rejects merge commits. Use `abortOnConflict: false` to pause on conflicts instead of aborting. |

### 3. Execute safely

- Prefer `autoStash: true` when the working tree is dirty.
  - `rebaseWithPlan` uses git's native `--autostash`.
  - `amendLastCommit` uses `--keep-index` mode (preserves staged changes).
  - `splitCommit` and `cherryPickSingle` use git-hex's own stash helper.
- Never rewrite shared or protected branches — only feature branches the user
  controls.
- All write operations create backup refs automatically.

### 4. Handle stash restore failures

Tools that manage their own stash (`amendLastCommit`, `splitCommit`,
`cherryPickSingle`) return `stashNotRestored: true` if the stash pop fails
after the operation succeeds. When you see this:

1. Tell the user their operation succeeded but their stashed changes couldn't
   be reapplied cleanly.
2. Suggest running `git stash list` to find the stash entry, then
   `git stash pop` manually to resolve any conflicts.

`rebaseWithPlan` uses git's native `--autostash` and does not emit this flag —
git handles it internally.

### 5. Recover from mistakes

- Call `git-hex-undoLast` to restore the state before the last git-hex
  operation.
- It requires a clean working tree. Use `force: true` only if commits were
  added after the backup or untracked files would be overwritten.
- If a rebase pauses with conflicts, hand off to the
  **git-hex-conflict-resolution** skill.

## Gotchas

- **`reword` requires `message`** — without it, git opens an editor and hangs.
- **Messages must be single-line** — no TAB or newline characters in `message`
  fields for `reword`, `splitCommit`, or `createFixup`.
- **`createFixup` needs staged changes** — it doesn't stage anything itself.
  Remind the user to `git add` first.
- **`requireComplete: true`** — when reordering, every commit in the range must
  appear in the plan. Without this, unmentioned commits default to `pick`.
- **Prefer `fixup` over `squash`** unless the user wants to combine commit
  messages (squash opens an editor-like message merge; fixup silently discards).
- **Root commits can't be split** — `splitCommit` rejects them.
- **Merge commits can't be split or cherry-picked** — both tools reject them.
- **Detached HEAD** — `getRebasePlan` and `rebaseWithPlan` warn about this in
  their summary. Flag it to the user if unexpected.
