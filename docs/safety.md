# Safety

git-hex is designed for Git history refactoring (rebases, fixups, amend, split-by-file) without requiring an interactive terminal.

## Safety first (what’s protected by default)

- **Scoped filesystem access**: when MCP `roots` are configured, repository paths are validated to stay within allowed roots.
- **Conflict safety**: operations that can conflict (rebase, cherry-pick) abort and restore the repository by default.
- **Backups for mutating ops**: every history-mutating operation creates a backup ref under `refs/git-hex/backup/...` (and updates `refs/git-hex/last/...`).
- **Read-only mode**: set `GIT_HEX_READ_ONLY=1` to block all mutating tools.

## Operational guarantees (scoped)

- git-hex tools do **not** run `git push`, `git fetch`, or `git pull`. Any remote operations are performed explicitly by you/your client.
- During tool execution, git-hex operates on the target repository via local `git` commands; dependency installation (framework) may use the network unless you preinstall/pin it.

## Read-only mode

Enable:

```bash
export GIT_HEX_READ_ONLY=1
```

In this mode:
- ✅ `git-hex-getRebasePlan` — allowed (inspection only)
- ❌ `git-hex-rebaseWithPlan` — blocked
- ❌ `git-hex-createFixup` — blocked
- ❌ `git-hex-amendLastCommit` — blocked
- ❌ `git-hex-cherryPickSingle` — blocked
- ❌ `git-hex-undoLast` — blocked

Blocked tools return error code `-32602` with a clear message explaining that read-only mode is active.

## Recovery

### `git-hex-undoLast`

```json
{ "tool": "git-hex-undoLast", "arguments": {} }
```

`undoLast` refuses to run if new commits were added after the backup ref; set `force` to `true` to discard those commits explicitly.

### Git reflog (manual recovery)

```bash
git reflog
git reset --hard HEAD@{2}
```

### Backup refs (manual recovery)

```bash
git for-each-ref refs/git-hex/
git reset --hard refs/git-hex/backup/<timestamp>_<operation>
```

## When not to use git-hex

- On shared/protected branches (use personal feature branches only).
- For hunk-level splitting (`splitCommit` is file-level only).
- On repositories where you don’t control/understand the project’s history-rewrite policy.

