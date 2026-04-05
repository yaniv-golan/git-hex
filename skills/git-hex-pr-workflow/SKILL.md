---
name: git-hex-pr-workflow
description: >
  Trigger whenever the user's message contains "PR", "pull request", or "review
  feedback" — regardless of what else they ask for. This includes: "open a PR",
  "create a PR", "prepare for PR", "update my PR", "clean up and open a pull
  request", "address review comments", "reviewer wants", "PR #number". Even if
  the request also involves squashing, rebasing, or fixing commits, trigger this
  skill as long as a PR or review is part of the goal. Do NOT trigger for
  local-only git work (squash, amend, cherry-pick, rebase, conflict resolution)
  where no pull request or code review is mentioned. Do NOT trigger for branch
  protection rules or repo settings.
---

# Git-hex PR Workflow

Use this skill when the user wants to go from a messy feature branch to a
clean, submitted (or updated) pull request. This skill combines git-hex for
local commit shaping with GitHub tools or CLI for remote collaboration.

## Workflow

### Phase 1: Understand the branch

1. Call `git-hex-getRebasePlan` with `onto` set to the target branch (usually
   `main` or `origin/main`) to see all commits that will be in the PR.
2. Call `git-hex-checkRebaseConflicts` with the same `onto` to predict whether
   rebasing will be smooth. If conflicts are predicted, warn the user before
   proceeding — they may want to resolve upstream changes first.

### Phase 2: Shape the history

Use the **git-hex-branch-cleanup** skill techniques to craft a clean, logical
commit sequence. Common PR prep patterns:

- **Squash WIP commits**: Use `rebaseWithPlan` with `fixup` actions to collapse
  work-in-progress into meaningful commits.
- **Separate concerns**: Use `splitCommit` to break a large commit into focused,
  reviewable pieces (e.g., separate refactoring from feature work).
- **Reword for clarity**: Use `rebaseWithPlan` with `reword` actions to write
  commit messages that tell the PR's story.
- **Rebase onto latest main**: Use `rebaseWithPlan` with `onto: "origin/main"`
  and an empty plan to fast-forward the base.

### Phase 3: Push and create the PR

1. **Push**: `git push --force-with-lease` (safe force push — refuses if
   the remote has commits you haven't seen).
   - For first push: `git push -u origin <branch>`.
   - Never force-push to main/master.

2. **Create or update the PR**:
   - Use `gh pr create` (or the GitHub plugin if installed).
   - **Craft the PR description from the commit history**: Use the commits from
     `getRebasePlan` to build a summary. Each well-crafted commit message
     becomes a bullet point or section in the PR body.

   ```
   gh pr create --title "Short title" --body "$(cat <<'EOF'
   ## Summary
   - First logical change (from commit 1 message)
   - Second logical change (from commit 2 message)

   ## Test plan
   - [ ] Verify X
   - [ ] Check Y
   EOF
   )"
   ```

### Phase 4: Address review feedback

When the user gets review comments and wants to update the PR:

1. **Make the fix** — edit the code as needed.
2. **Target the right commit** — use `git-hex-createFixup` pointing at the
   commit the review comment refers to. This keeps the fix associated with
   the original change.
3. **Fold it in** — `git-hex-rebaseWithPlan` with `autosquash: true` to
   absorb the fixup commit.
4. **Push again** — `git push --force-with-lease`.

This produces a clean history where each commit is correct, rather than a
trail of "fix review comment" commits.

### Phase 5: Handle stacked PRs (advanced)

When working with dependent branches:

1. Rebase child branches after parent is rebased:
   `git-hex-rebaseWithPlan` with `onto` set to the rebased parent.
2. Use `git-hex-checkRebaseConflicts` to preview whether the child rebase
   will conflict.
3. Push each branch with `--force-with-lease`.

## Tools to prefer

- **Local craft**: All git-hex tools (see branch-cleanup skill for details)
- **Remote**: GitHub plugin tools if installed; otherwise `gh` CLI

## Key insight

git-hex handles the **local craft** — shaping commits into a clean, reviewable
story. GitHub tools handle the **remote collaboration** — creating PRs, adding
reviewers, responding to comments. Together they cover the full PR lifecycle.

## Gotchas

- **Always fetch before rebasing onto main**: `git fetch origin` first,
  then use `origin/main` as the `onto` target.
- **`--force-with-lease` not `--force`**: The lease check prevents overwriting
  teammates' pushes.
- **Review feedback fixups need staging**: `createFixup` requires staged
  changes — remind the user to `git add` the fix first.
- **PR description gets stale after rebase**: If you rewrote history, update
  the PR description to match the new commits.
