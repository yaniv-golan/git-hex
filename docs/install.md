# Installation

## Recommended: `git-hex.sh` wrapper (auto-installs prerequisites)

```bash
git clone https://github.com/yaniv-golan/git-hex.git ~/git-hex
cd ~/git-hex
./git-hex.sh doctor          # diagnostics (read-only; no persistent changes)
./git-hex.sh doctor --fix    # installs/repairs prerequisites (including the framework)
```

On first run (or during `doctor --fix`), you may see framework installation output like “Installing mcp-bash framework …”; this is normal.

## What `doctor --fix` may write (managed default install)

When `MCPBASH_HOME` is **not** set, `git-hex.sh` manages the MCP Bash Framework install at:

- `${XDG_DATA_HOME:-$HOME/.local/share}/mcp-bash`

During `doctor --fix` (or first run with auto-install enabled), it may:

- Create/replace the framework directory at the managed path above (via a staged/atomic directory swap).
- Create a convenience launcher at `${HOME}/.local/bin/mcp-bash` (symlink when possible; otherwise a small shim script).
- Create temporary staging directories alongside the target (e.g., `mcp-bash.stage.*`) during install.

It does **not** modify your git configuration or repositories during install.

### User-managed installs (`MCPBASH_HOME`)

If `MCPBASH_HOME` is set, that install is treated as user-managed:

- `./git-hex.sh doctor` will use it.
- `./git-hex.sh doctor --fix` will refuse to modify it (policy refusal), and will instruct you to upgrade it yourself.

## Verified framework install (recommended for CI / supply-chain conscious setups)

Set a checksum to force a verified tarball install of the pinned framework version:

```bash
export GIT_HEX_MCPBASH_SHA256="488469bbc221b6eb9d16d6eec1d85cdd82f49ae128b30d33761e8edb9be45349"
./git-hex.sh doctor --fix
```

Optional: override the archive URL used with `GIT_HEX_MCPBASH_ARCHIVE_URL` if you mirror artifacts.

## Network behavior (scoped)

- During tool execution on a repository, git-hex does not need network access.
- Installation/upgrade of the MCP Bash Framework may use the network (download tarball or clone a pinned commit) unless you preinstall/manage it yourself.

## Uninstall / cleanup

### Remove git-hex

```bash
rm -rf ~/git-hex
```

### Remove the managed framework install (only if you used the managed default)

```bash
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/mcp-bash"
rm -f "${HOME}/.local/bin/mcp-bash"
```

If you set `MCPBASH_HOME`, remove that install according to how you manage it.
