# git-hex Standalone MCP Server Release Plan

**Status**: Draft (aligned with mcp-bash v0.4.0)  
**Date**: 2025-12-06  
**Author**: AI-assisted planning

## Overview

This document outlines the process, rationale, and options for releasing an MCP server as a standalone tool in its own repository, implemented using the mcp-bash framework.

The canonical example used throughout is **git-hex** — an interactive git refactoring MCP server — but the patterns apply to any standalone MCP tool.

This plan assumes:
- mcp-bash framework **v0.4.0 or later**, which includes:
  - One-line installer (`install.sh`)
  - Project CLI commands: `mcp-bash init`, `mcp-bash scaffold server`, `mcp-bash scaffold tool`, `mcp-bash scaffold test`, `mcp-bash validate`, `mcp-bash config`, `mcp-bash doctor`, `mcp-bash run-tool`
  - Typed argument helpers in the SDK: `mcp_args_bool`, `mcp_args_int`, `mcp_args_require`
  - Path validation helper `mcp_require_path` with shared normalization and MCP roots enforcement
  - Automatic project root detection when running inside a project directory
- A POSIX shell environment (macOS, Linux, WSL, or Git Bash on Windows)

**v0.4.0 alignment in this plan**:
- Tool templates and examples use `mcp_require_path`, `mcp_args_bool`, `mcp_args_int`, and `mcp_args_require` for input handling.
- Validation/testing steps incorporate `mcp-bash run-tool` for direct tool execution and `mcp-bash scaffold test` for the generated harness.
- Path handling guidance assumes the shared normalization layer from `lib/path.sh`.

---

## Rationale

### Why Standalone Repositories?

1. **Focused Distribution**: Users interested in git tools don't need the full mcp-bash examples/docs
2. **Independent Versioning**: Tool can evolve on its own release cadence
3. **Discoverability**: Separate repo appears in GitHub searches, MCP registries, etc.
4. **Community Ownership**: Different maintainers can own different tools
5. **Reduced Coupling**: Framework updates don't force tool releases (and vice versa)

### Why mcp-bash as the Runtime?

1. **Zero Runtime Dependencies**: No Node.js, Python, or other runtimes required
2. **Protocol Compliance**: Full MCP 2025-06-18 support out of the box
3. **Battle-Tested**: Handles concurrency, timeouts, cancellation, progress reporting
4. **Minimal Ceremony**: Tool authors write bash scripts, not protocol handlers
5. **Cross-Platform**: Works on macOS, Linux, WSL, Git Bash

---

## Architecture Model (Framework v0.4.0)

```
┌─────────────────────────────────────────────────────────────────┐
│                     User's MCP Client                           │
│              (Claude Desktop, Cursor, Windsurf, etc.)           │
└─────────────────────────┬───────────────────────────────────────┘
                          │ stdio (JSON-RPC 2.0)
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   mcp-bash Framework                            │
│  ~/mcp-bash-framework/                                          │
│  ├── bin/mcp-bash         ◄── Entry point                       │
│  ├── lib/                 ◄── Protocol handlers                 │
│  ├── handlers/            ◄── JSON-RPC dispatch                 │
│  └── sdk/tool-sdk.sh      ◄── Tool runtime helpers              │
└─────────────────────────┬───────────────────────────────────────┘
                          │ MCPBASH_PROJECT_ROOT
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Standalone Tool Project                       │
│  ~/git-hex/                                                     │
│  ├── server.d/server.meta.json   ◄── Server identity            │
│  ├── tools/                                                     │
│  │   ├── get-rebase-plan/                                       │
│  │   │   ├── tool.meta.json      ◄── MCP schema                 │
│  │   │   └── tool.sh             ◄── Implementation             │
│  │   ├── perform-rebase/                                        │
│  │   └── create-fixup/                                          │
│  └── .registry/                  ◄── Auto-generated cache       │
└─────────────────────────────────────────────────────────────────┘
```

**Key Insight**: The framework is installed once and shared. Each standalone tool is a separate "project" that the framework loads:
- Automatically when you run `mcp-bash` **inside** the project directory (auto-detects `server.d/server.meta.json` up the tree), or
- Explicitly when the MCP client sets `MCPBASH_PROJECT_ROOT` to the project path.
- Directly for local testing via `mcp-bash run-tool <tool-name>` (respects `MCPBASH_PROJECT_ROOT`, supports `--roots`, `--timeout`, `--dry-run`, `--verbose` stderr streaming, and `--print-env` to inspect wiring).

---

## Project Structure Specification

### Minimum Viable Structure (v0.4.0+)

```
my-mcp-tool/
├── server.d/
│   └── server.meta.json         # Server identity (name/title/version)
├── tools/
│   └── my-tool/
│       ├── tool.sh              # Required: executable script
│       └── tool.meta.json       # Required: MCP tool schema
└── .gitignore                   # Should ignore .registry/ and logs
```

### Recommended Full Structure

```
my-mcp-tool/
├── server.d/
│   └── server.meta.json         # Server identity (name, version, description)
├── tools/
│   ├── tool-one/
│   │   ├── tool.sh
│   │   └── tool.meta.json
│   └── tool-two/
│       ├── tool.sh
│       └── tool.meta.json
├── lib/                         # Optional: shared utilities
│   └── helpers.sh
├── resources/                   # Optional: static resources
├── prompts/                     # Optional: prompt templates
├── test/                        # Optional: generated via `mcp-bash scaffold test`
│   ├── README.md
│   └── run.sh
├── .gitignore
├── README.md
├── LICENSE
└── VERSION                      # Optional: version file (read by framework)
```

---

## File Specifications

### `server.d/server.meta.json`

Defines server identity in MCP `initialize` response.

```json
{
  "name": "git-hex",
  "title": "Git Hex",
  "version": "1.0.0",
  "description": "Interactive git refactoring via MCP",
  "websiteUrl": "https://github.com/yaniv-golan/git-hex",
  "icons": [
    {"src": "https://example.com/icon.svg", "sizes": ["any"], "mimeType": "image/svg+xml"}
  ]
}
```

**Defaults when omitted**:
- `name`: Directory name of `MCPBASH_PROJECT_ROOT`
- `title`: Titlecase of name
- `version`: From `VERSION` file, `package.json`, or `0.0.0`

### `tools/*/tool.meta.json`

Defines MCP tool schema per [MCP Tool specification](https://spec.modelcontextprotocol.io/specification/server/tools/).

```json
{
  "name": "gitHex.getRebasePlan",
  "description": "Get structured rebase plan for last N commits",
  "inputSchema": {
    "type": "object",
    "properties": {
      "count": { "type": "integer", "description": "Number of commits (default 10)" },
      "onto": { "type": "string", "description": "Base ref to rebase onto" }
    }
  },
  "outputSchema": {
    "type": "object",
    "properties": {
      "plan_id": { "type": "string" },
      "commits": { "type": "array" }
    }
  },
  "timeoutSecs": 30
}
```

**Required fields**: `name`, `inputSchema`  
**Recommended fields**: `description` (validation warns if missing)  
**Optional fields**: `outputSchema`, `timeoutSecs` (default: framework default)

### `tools/*/tool.sh`

Executable bash script implementing the tool logic.

**Canonical v0.4.0 pattern** (typed args + roots enforcement with shared normalization):

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
include_untracked="$(mcp_args_bool '.includeUntracked' --default false)"
limit="$(mcp_args_int '.limit' --default 20 --min 1 --max 200)"
operation="$(mcp_args_require '.operation')"

# Validate
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
    mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

# Do work...

# Emit result (using JSON helper)
mcp_emit_json "$(mcp_json_obj \
    repoPath "${repo_path}" \
    operation "${operation}" \
    includeUntracked "${include_untracked}" \
    limit "${limit}" \
)"
```

**SDK Functions Available**:

| Function | Purpose | Example |
|----------|---------|---------|
| `mcp_args_require` | Extract required string, fail if missing | `pattern="$(mcp_args_require '.pattern')"` |
| `mcp_args_bool` | Parse boolean with default | `verbose="$(mcp_args_bool '.verbose' --default false)"` |
| `mcp_args_int` | Parse integer with optional bounds/default | `count="$(mcp_args_int '.count' --default 10 --min 1 --max 200)"` |
| `mcp_require_path` | Normalize and enforce roots for paths | `repo="$(mcp_require_path '.repoPath' --default-to-single-root)"` |
| `mcp_args_get '.field'` | Extract argument using jq filter | `onto="$(mcp_args_get '.onto // \"main\"')" ` |
| `mcp_args_raw` | Get raw JSON arguments | `args_json="$(mcp_args_raw)"` |
| `mcp_emit_json '{...}'` | Output JSON result | `mcp_emit_json "$(mcp_json_obj status "ok")"` |
| `mcp_emit_text "..."` | Output plain text result | `mcp_emit_text "done"` |
| `mcp_json_obj k1 v1 ...` | Build JSON object safely | `mcp_json_obj repo "${repo}" count "${count}"` |
| `mcp_json_arr v1 v2 ...` | Build JSON array safely | `mcp_json_arr "${a}" "${b}"` |
| `mcp_json_escape "value"` | Escape string for JSON | `escaped="$(mcp_json_escape "${text}")"` |
| `mcp_fail CODE "message"` | Exit with MCP error | `mcp_fail -32603 "git failure"` |
| `mcp_fail_invalid_args "msg"` | Exit with -32602 | `mcp_fail_invalid_args "count must be >=1"` |
| `mcp_progress PERCENT "msg"` | Report progress | `mcp_progress 50 "halfway"` |
| `mcp_log_info LOGGER "msg"` | Send log notification | `mcp_log_info git-hex "starting"` |
| `mcp_log_debug LOGGER "msg"` | Send debug log notification | `mcp_log_debug git-hex "args: ${args_json}"` |
| `mcp_log_warn LOGGER "msg"` | Send warning log notification | `mcp_log_warn git-hex "retrying"` |
| `mcp_log_error LOGGER "msg"` | Send error log notification | `mcp_log_error git-hex "failed"` |
| `mcp_is_cancelled` | Check if client cancelled request | `if mcp_is_cancelled; then exit 0; fi` |

**Roots helpers** (for path validation when `mcp_require_path` is not sufficient):

| Function | Purpose |
|----------|---------|
| `mcp_roots_list` | Get newline-separated list of root paths |
| `mcp_roots_count` | Get number of configured roots |
| `mcp_roots_contains PATH` | Check if path is within any root (returns 0/1) |

**Elicitation helpers** (for user input):

| Function | Purpose |
|----------|---------|
| `mcp_elicit MESSAGE SCHEMA` | Request structured user input |
| `mcp_elicit_string MESSAGE` | Request a string value from user |
| `mcp_elicit_confirm MESSAGE` | Request yes/no confirmation |
| `mcp_elicit_choice MESSAGE OPT1 OPT2...` | Request selection from options |

> **Full SDK reference**: See [`sdk/tool-sdk.sh`](https://github.com/yaniv-golan/mcp-bash-framework/blob/main/sdk/tool-sdk.sh) for complete documentation.

---

## Tool Naming Convention

Tool names should follow a consistent pattern for discoverability and collision avoidance.

### Recommended Pattern

| Component | Convention | Example |
|-----------|------------|---------|
| **Tool name in `tool.meta.json`** | `namespace.camelCase` | `"name": "gitHex.getRebasePlan"` |
| **Directory name** | `kebab-case` | `tools/get-rebase-plan/` |
| **Server name in `server.meta.json`** | `kebab-case` | `"name": "git-hex"` |

### Rationale

1. **Namespacing** (e.g., `gitHex.`) prevents collisions when multiple MCP servers are active in the same client
2. **camelCase** for JSON fields matches JavaScript/JSON conventions
3. **kebab-case** for directories is cross-platform safe and bash-friendly

### Examples

```json
// tools/get-rebase-plan/tool.meta.json
{
  "name": "gitHex.getRebasePlan",
  "description": "Get structured rebase plan for last N commits",
  "inputSchema": { ... }
}

// tools/perform-rebase/tool.meta.json
{
  "name": "gitHex.performRebase",
  "description": "Execute interactive rebase with abort-on-conflict",
  "inputSchema": { ... }
}
```

### Validation

Run `mcp-bash validate` to check naming conventions. The validator warns if:
- Tool names lack a namespace prefix
- Names contain invalid characters
- Names exceed recommended length (64 chars)

---

## Distribution Options

### Option A: Separate Framework Install (Recommended)

**User workflow**:
```bash
# One-time framework install (choose one)

# Option 1: One-line installer (recommended; requires bash + git + curl)
curl -fsSL https://raw.githubusercontent.com/yaniv-golan/mcp-bash-framework/main/install.sh | bash

# Option 2: Manual install
git clone https://github.com/yaniv-golan/mcp-bash-framework.git ~/mcp-bash-framework
export PATH="$HOME/mcp-bash-framework/bin:$PATH"

# Clone tool project (git-hex)
git clone https://github.com/yaniv-golan/git-hex.git ~/git-hex

# Optional: sanity checks from inside the project
cd ~/git-hex
mcp-bash doctor --json           # environment + project diagnostics (machine-readable)
mcp-bash validate --json --strict # validate metadata/scripts; fail on warnings
mcp-bash config --json           # print MCP client config snippets (machine-readable)
mcp-bash config --wrapper >run.sh # generate auto-install wrapper script
chmod +x run.sh
mcp-bash run-tool get-rebase-plan --roots . --dry-run --print-env # direct invocation for smoke tests
```

**MCP client config**:
```json
{
  "mcpServers": {
    "git-hex": {
      "command": "/Users/me/mcp-bash-framework/bin/mcp-bash",
      "env": { "MCPBASH_PROJECT_ROOT": "/Users/me/git-hex" }
    }
  }
}
```

**Pros**:
- Clean separation of concerns
- Framework updates independent of tool
- Smallest tool repository size
- Multiple tools share one framework install

**Cons**:
- Two repositories to clone
- Users must manage framework path

**Best for**: Power users, multiple MCP tools, CI/CD environments

---

### Option B: Wrapper Script (Recommended for Quick Start)

Include a small wrapper that downloads/locates the framework automatically. You can generate it via `mcp-bash config --wrapper > run.sh` or use the template below.

**`run.sh`**:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="${MCPBASH_HOME:-$HOME/mcp-bash-framework}"

# Auto-install framework if missing
if [ ! -f "${FRAMEWORK_DIR}/bin/mcp-bash" ]; then
    echo "Installing mcp-bash framework..." >&2
    git clone --depth 1 https://github.com/yaniv-golan/mcp-bash-framework.git "${FRAMEWORK_DIR}"
fi

export MCPBASH_PROJECT_ROOT="${SCRIPT_DIR}"
exec "${FRAMEWORK_DIR}/bin/mcp-bash" "$@"
```

**MCP client config**:
```json
{
  "mcpServers": {
    "git-hex": {
      "command": "/Users/me/git-hex/run.sh"
    }
  }
}
```

**Pros**:
- Single command entry point
- Auto-installs framework on first run
- Respects `MCPBASH_HOME` override
- Zero-config for end users

**Cons**:
- Network access on first run
- Git required
- Less explicit about dependencies

**Best for**: Quick-start experience, demos, users who want "just works" behavior

---

### Option C: Docker Image

**Dockerfile**:
```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y bash jq git && \
    rm -rf /var/lib/apt/lists/*

# Install framework
RUN git clone --depth 1 https://github.com/yaniv-golan/mcp-bash-framework.git /mcp-bash-framework

# Copy tool
COPY . /app
ENV MCPBASH_PROJECT_ROOT=/app

ENTRYPOINT ["/mcp-bash-framework/bin/mcp-bash"]
```

**Usage with MCP clients supporting Docker**:
```json
{
  "mcpServers": {
    "my-tool": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "my-tool:latest"]
    }
  }
}
```

**Pros**:
- Fully isolated environment
- Reproducible across platforms
- No local dependencies

**Cons**:
- Docker required
- Larger distribution size
- Filesystem access requires volume mounts

**Best for**: Enterprise deployments, CI/CD, tools requiring specific dependencies

---

### Option D: Git Submodule (Advanced)

For users who need strict version pinning and prefer a single-repo clone.

**Repository setup**:
```bash
cd my-mcp-tool
git submodule add https://github.com/yaniv-golan/mcp-bash-framework.git mcp-bash-framework
```

**Structure**:
```
my-mcp-tool/
├── mcp-bash-framework/          # Submodule
├── tools/
├── server.d/
└── README.md
```

**MCP client config**:
```json
{
  "mcpServers": {
    "my-tool": {
      "command": "/Users/me/my-mcp-tool/mcp-bash-framework/bin/mcp-bash",
      "env": { "MCPBASH_PROJECT_ROOT": "/Users/me/my-mcp-tool" }
    }
  }
}
```

**Pros**:
- Single `git clone --recursive` for users
- Pinned framework version per tool release
- Self-contained distribution

**Cons**:
- Larger repository size
- Submodule complexity (users often forget `--recursive`)
- Framework updates require submodule bump

**Best for**: Stable tools with infrequent updates, enterprise environments requiring version pinning

---

## Distribution Comparison Matrix

| Aspect | Option A (Separate) | Option B (Wrapper) | Option C (Docker) | Option D (Submodule) |
|--------|---------------------|--------------------|--------------------|----------------------|
| User complexity | Medium | **Low** | Medium | Medium |
| Repository size | **Smallest** | **Smallest** | N/A | Medium |
| Framework updates | Independent | Auto on first run | Rebuild image | Manual bump |
| Offline install | ❌ | ❌ | ✅ | ✅ |
| CI/CD friendly | ✅ | ⚠️ | ✅✅ | ✅ |
| Version pinning | ❌ | ❌ | ✅ | ✅ |
| Zero-config | ❌ | **✅** | ❌ | ❌ |

**Recommendation**: 
- **Option A** (separate install) for power users and CI/CD
- **Option B** (wrapper script) for quick-start and demos
- **Option C** (Docker) for enterprise/isolated deployments
- **Option D** (submodule) only when strict version pinning is required

> **Note**: npm/npx distribution is not applicable to bash-based tools. The mcp-bash framework is shell-native and doesn't require Node.js.

---

## Implementation Checklist

### Phase 1: Project Setup (Automated)

```bash
mkdir git-hex && cd git-hex
mcp-bash init --name git-hex
mcp-bash scaffold test           # generates test/run.sh harness (v0.4.0)
```

This automatically creates:
- [x] `.gitignore` (ignores `.registry/`, `*.log`, `.DS_Store`)
- [x] `server.d/server.meta.json` with server identity
- [x] `tools/hello/` working example tool
- [x] `test/run.sh` + `test/README.md` harness ready for `run-tool`
- [x] Proper directory structure

### Phase 2: Server Configuration

- [ ] Edit `server.d/server.meta.json` to customize:
  - [ ] `name` - server identifier
  - [ ] `title` - human-readable name
  - [ ] `version` - semantic version
  - [ ] `description` - what the server does
  - [ ] `websiteUrl` - link to repo/docs (optional)
- [ ] Verify name follows MCP naming conventions (lowercase, hyphens)

### Phase 3: Tool Implementation

For each tool:

```bash
mcp-bash scaffold tool <tool-name>
```

Then:
- [ ] Edit `tool.meta.json` with complete `inputSchema`
- [ ] Implement tool logic in `tool.sh` using `mcp_require_path` for any path args and the typed helpers (`mcp_args_bool` / `mcp_args_int` / `mcp_args_require`) for validation
- [ ] Add error handling with `mcp_fail_invalid_args` and `mcp_fail`
- [ ] Add progress/logging as needed with `mcp_progress` and `mcp_log_*`
- [ ] Test locally with `mcp-bash run-tool <tool> --roots . --dry-run` (or `--print-env` + `--dry-run` to inspect wiring) before wiring clients

### Phase 4: Remove Placeholder

- [ ] Delete `tools/hello/` once you have real tools

### Phase 5: Validation & Smoke Tests

```bash
mcp-bash validate --json --strict
mcp-bash run-tool <tool-name> --roots . --timeout 30 --verbose
```
`--roots` accepts a comma-separated list of allowed paths; `--verbose` streams the tool's stderr once without re-running the tool; `--print-env` dumps wiring without executing.
Optionally:

```bash
mcp-bash validate --explain-defaults   # human-friendly defaults summary
mcp-bash config --json                  # machine-readable descriptor (name/command/env)
mcp-bash config --wrapper               # generate auto-install wrapper script
mcp-bash doctor --json                  # framework + project diagnostics
mcp-bash registry status                # inspect registry cache state (hash/mtime/counts)
```

- [ ] All tools pass `mcp-bash validate` (no errors)
- [ ] `mcp-bash run-tool` succeeds for happy paths and surfaces stderr once on failures
- [ ] No JSON syntax errors in `server.meta.json` / `tool.meta.json`
- [ ] All scripts executable (or auto-fixed via `mcp-bash validate --fix`)

### Phase 6: Documentation

- [ ] Edit `README.md` with:
  - [ ] Description and features
  - [ ] Requirements (bash, jq, tool-specific deps)
  - [ ] Installation instructions (framework + tool)
  - [ ] MCP client configuration (use `mcp-bash config --client` / `--json` output)
  - [ ] Tool documentation with examples
  - [ ] How to run `mcp-bash run-tool` for quick checks (roots/timeout/dry-run/print-env)
  - [ ] License
- [ ] Add `CHANGELOG.md` for release notes
- [ ] Add `LICENSE` file (MIT recommended)

### Phase 7: Testing

See the dedicated **[Testing git-hex](#testing-git-hex-comprehensive-strategy)** section below for comprehensive testing guidance.

**Quick validation**:
```bash
# CLI harness generated by scaffold test (wraps run-tool)
./test/run.sh <tool-name> --roots . --args '{"example":true}'

# Test with MCP Inspector (interactive)
npx @modelcontextprotocol/inspector --transport stdio -- mcp-bash

# Get config for real clients
mcp-bash config --client claude-desktop  # pasteable JSON
mcp-bash config --wrapper                # generate wrapper script
```

**MCP Inspector workflow**:
1. Run the command above from your project directory
2. Click **"Initialize"** in Inspector to start the MCP session
3. Go to **"Tools"** tab to see your registered tools
4. Click a tool, fill in test arguments, and click **"Call Tool"**
5. Verify the response matches expectations
6. Test error cases by providing invalid arguments

- [ ] Test with generated CLI harness (`./test/run.sh`)
- [ ] Test with MCP Inspector
- [ ] Test with target MCP clients (Claude Desktop, Cursor, etc.)
- [ ] Test error cases (missing args, invalid input, tool failures)
- [ ] Test on target platforms (macOS, Linux, WSL if applicable)
- [ ] Set up CI pipeline (see GitHub Actions example below)

### Phase 8: Release

```bash
git init
git add .
git commit -m "Initial commit"
git tag v1.0.0
git remote add origin https://github.com/you/my-mcp-server.git
git push -u origin main --tags
```

- [ ] Create GitHub release with changelog
- [ ] Submit to MCP registries (if applicable)

---

## Example: git-hex Implementation

### Quick Start

```bash
# Create project
mkdir git-hex && cd git-hex
mcp-bash init --name git-hex
mcp-bash scaffold test  # generate test harness (wraps run-tool)

# Add tools
mcp-bash scaffold tool get-rebase-plan
mcp-bash scaffold tool perform-rebase
mcp-bash scaffold tool create-fixup
mcp-bash scaffold tool amend-last-commit
mcp-bash scaffold tool cherry-pick-single

# Remove placeholder
rm -rf tools/hello

# Implement, validate, ship
# ... edit tool files ...
mcp-bash run-tool get-rebase-plan --roots . --dry-run
mcp-bash run-tool perform-rebase --roots . --args '{"onto":"main"}' --dry-run
mcp-bash run-tool create-fixup --roots . --args '{"commit":"HEAD~1"}' --dry-run
mcp-bash run-tool amend-last-commit --roots . --args '{"message":"wip"}' --dry-run
mcp-bash run-tool cherry-pick-single --roots . --args '{"commit":"abc123"}' --dry-run
mcp-bash validate
git init && git add . && git commit -m "Initial commit"
```

### Tool Mapping

| Original Function | mcp-bash Tool |
|-------------------|---------------|
| `get_rebase_plan()` | `tools/get-rebase-plan/tool.sh` |
| `perform_rebase()` | `tools/perform-rebase/tool.sh` |
| `create_fixup()` | `tools/create-fixup/tool.sh` |
| `amend_last_commit()` | `tools/amend-last-commit/tool.sh` |
| `cherry_pick_single()` | `tools/cherry-pick-single/tool.sh` |

### Code Adaptations (v0.4.0 helpers)

| Original Pattern | mcp-bash Pattern |
|------------------|------------------|
| Manual path validation against roots | `repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"` |
| `echo "$2" \| jq -r '.count'` | `count="$(mcp_args_int '.count' --default 10 --min 1 --max 200)"` |
| Manual boolean parsing | `include_untracked="$(mcp_args_bool '.includeUntracked' --default false)"` |
| Required string checks with `[ -z ... ]` | `operation="$(mcp_args_require '.operation')" ` |
| `send_text "$1"` | `mcp_emit_text "$1"` |
| `send_json "$1"` | `mcp_emit_json "$1"` |
| `send_error "$1"` | `mcp_fail -32603 "$1"` |
| `jq -n --arg x "$x" '{key:$x}'` | `mcp_json_obj key "$x"` |
| `case "$1" in get_rebase_plan)` | Not needed (framework routes by tool name) |
| Inline JSON schema | Separate `tool.meta.json` files |

### Minimal Tool Template (v0.4.0 helpers)

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

# Parse arguments
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"
count="$(mcp_args_int '.count' --default 10 --min 1 --max 200)"
include_untracked="$(mcp_args_bool '.includeUntracked' --default false)"

# Validate
if ! git -C "${repo_path}" rev-parse --git-dir >/dev/null 2>&1; then
    mcp_fail_invalid_args "Not a git repository at ${repo_path}"
fi

# Your logic here...

# Return result
mcp_emit_json "$(mcp_json_obj \
    plan_id "abc123" \
    repoPath "${repo_path}" \
    count "${count}" \
    includeUntracked "${include_untracked}" \
)"
```

**Note:** Boilerplate stays minimal (shebang, strict mode, SDK source) while typed helpers handle validation in-line.

### Cleanup Handling

The original implementation uses `trap cleanup EXIT`. This pattern is fully supported:

```bash
cleanup() {
    rm -f /tmp/git_todo_*_$$
    git rebase --abort >/dev/null 2>&1 || true
}
trap cleanup EXIT
```

The framework does not interfere with tool-level traps.

### Recommended Tool Set (Focused Scope)

git-hex should remain focused on "rebase & commit perfection" rather than becoming a general-purpose git tool. The recommended tool set:

| Tool | Purpose | Risk Level |
|------|---------|------------|
| `get-rebase-plan` | Analyze commits for interactive rebase | Read-only |
| `perform-rebase` | Execute rebase with abort-on-conflict | Medium (recoverable) |
| `create-fixup` | Create fixup commits for later squash | Low |
| `amend-last-commit` | Amend HEAD with staged changes | Low |
| `cherry-pick-single` | Cherry-pick one commit with strategy option | Medium (recoverable) |

**Excluded by design:**
- Bulk history rewriting (`filter-branch` is deprecated, `filter-repo` requires Python)
- Multi-commit cherry-pick wizards (too much hidden state)
- General git operations (status, log, diff, blame) — these belong in a separate "git-inspector" server or existing tools

### Benchmarking

Before publishing performance claims, measure startup latency with `hyperfine`:

```bash
# Measure tool startup latency (the key metric for MCP tools)
hyperfine --warmup 3 --export-markdown bench.md \
  'mcp-bash run-tool gitHex.getRebasePlan --roots /path/to/repo --args "{\"count\":5}" --timeout 10'

# Compare against baseline (empty/minimal tool)
hyperfine --warmup 3 \
  'mcp-bash run-tool gitHex.getRebasePlan --roots . --args "{\"count\":1}" --print-env' \
  'mcp-bash run-tool hello --roots . --print-env'
```

**Guidelines**:
- Focus on **startup latency**, not just execution time
- Compare against your own baseline, not other MCP servers (different scope = unfair comparison)
- Publish only verified numbers in the README
- Include environment details (OS, hardware, git repo size)

---

## Security Considerations

### Security by Transport

Security requirements differ based on how the MCP server is accessed:

| Transport | Authentication | Path Validation | Secrets Management |
|-----------|----------------|-----------------|-------------------|
| **stdio (local)** | N/A (inherits shell permissions) | `mcp_require_path` + MCP roots | Environment variables only |
| **HTTP (remote)** | Out of scope for this framework (stdio-only transport) | N/A | N/A |

> **Note**: mcp-bash is stdio-only. git-hex and similar tools run with the same permissions as the MCP client (Claude Desktop, Cursor, etc.); HTTP/OAuth flows are not part of this release plan.

### Core Security Practices

1. **Input Validation**: Always validate arguments before use
2. **Path Traversal**: Use `mcp_require_path` for user-supplied paths; it normalizes and enforces MCP roots
3. **Command Injection**: Quote all variables in command execution
4. **Sensitive Data**: Never log credentials or tokens (use `mcp_log` carefully)
5. **Timeouts**: Set appropriate `timeoutSecs` to prevent hanging tools
6. **Cleanup**: Always clean up temp files, even on failure

### Safe Command Construction

Avoid command injection by properly quoting variables:

```bash
# ❌ DANGEROUS: Unquoted variable allows injection
git log --oneline -n $count

# ✅ SAFE: Quoted variable
git log --oneline -n "${count}"

# ✅ SAFER: Validate before use
count="$(mcp_args_int '.count' --default 10 --min 1 --max 200)"
git log --oneline -n "${count}"

# ❌ DANGEROUS: User input in command string
eval "git ${user_command}"

# ✅ SAFE: Explicit command with validated args
case "${operation}" in
    log) git log --oneline -n "${count}" ;;
    status) git status --porcelain ;;
    *) mcp_fail_invalid_args "Unknown operation: ${operation}" ;;
esac
```

### Path Security with MCP Roots

When MCP roots are configured, `mcp_require_path` ensures paths stay within allowed boundaries:

```bash
# This will fail if repo_path is outside configured roots
repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"

# Manual check if needed
if ! mcp_roots_contains "${some_path}"; then
    mcp_fail_invalid_args "Path is outside allowed roots"
fi
```

---

## Troubleshooting

### Common Issues

**`mcp-bash doctor` reports jq missing**:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# Windows (Git Bash)
# Download from https://jqlang.github.io/jq/download/
# Place jq.exe in a directory on your PATH
```

**Tool execution fails silently**:
1. Run `mcp-bash debug` instead of `mcp-bash` to enable payload logging
2. Check the debug log location printed to stderr
3. Look for JSON-RPC errors in the log file
4. Run `mcp-bash run-tool <tool> --roots . --verbose` to stream stderr once without re-executing the tool

**MCP client doesn't see tools**:
1. Verify `MCPBASH_PROJECT_ROOT` points to the correct directory
2. Run `mcp-bash validate` to check for metadata errors
3. Ensure `tool.sh` files are executable (`chmod +x`)
4. Check that `tool.meta.json` has valid JSON syntax

**"Method not found" errors**:
- Ensure the client completed initialization before calling tools
- Check that tool names in requests match `tool.meta.json` exactly

### Windows / Git Bash Specific

**Scripts not executable**:
- Windows doesn't honor Unix execute bits reliably
- The framework detects `.sh` extension as a fallback
- Run `mcp-bash validate --fix` to attempt permission fixes

**Path format issues**:

| Scenario | Behavior | Solution |
|----------|----------|----------|
| MCP client passes `C:\Users\...` | Framework normalizes automatically | No action needed |
| Tool calls external Windows commands | Path may be converted incorrectly | Set `MSYS2_ARG_CONV_EXCL=*` |
| Tool stores paths in JSON | Use POSIX format for consistency | Use `mcp_path_normalize` output |
| Symlinks in paths | May not resolve correctly | Avoid symlinks in cross-platform code |

**Example MCP client config for Windows**:
```json
{
  "mcpServers": {
    "git-hex": {
      "command": "C:\\Program Files\\Git\\bin\\bash.exe",
      "args": ["-c", "/c/Users/me/git-hex/run.sh"],
      "env": {
        "MCPBASH_PROJECT_ROOT": "/c/Users/me/git-hex",
        "MSYS2_ARG_CONV_EXCL": "*"
      }
    }
  }
}
```

**Process management limitations**:
- Job control (`jobs -p`) may not work in non-interactive shells
- Signal handling can be unreliable
- Keep tool implementations simple; avoid complex background processes

**Performance considerations**:
- Process creation overhead is higher on Windows
- Keep TTLs small and payload sizes bounded
- File I/O and stat operations are slower

### Debugging Tips

Enable verbose logging:
```json
{
  "env": {
    "MCPBASH_PROJECT_ROOT": "/path/to/project",
    "MCPBASH_LOG_LEVEL": "debug"
  }
}
```

Capture full payload traces:
```bash
mcp-bash debug
# Logs written to temp directory shown in stderr
```

Test a single tool manually:
```bash
cd /path/to/project
export MCP_SDK="/path/to/mcp-bash-framework/sdk"
export MCP_TOOL_ARGS_JSON='{"name":"test"}'
bash tools/my-tool/tool.sh
```

Prefer `mcp-bash run-tool` for day-to-day smoke tests; direct script execution is only needed when debugging SDK sourcing in isolation.

---

## Versioning Strategy

### Semantic Versioning

- **MAJOR**: Breaking changes to tool schemas or behavior
- **MINOR**: New tools or backward-compatible features
- **PATCH**: Bug fixes, documentation updates

### Framework Compatibility

Document minimum mcp-bash version in README:

```markdown
## Requirements

- mcp-bash framework v0.4.0 or later
```

Test against framework releases before publishing tool updates.

### Version Compatibility Matrix

| Feature | Minimum Version |
|---------|-----------------|
| `mcp-bash init` | v0.3.0 |
| `mcp-bash scaffold server/tool` | v0.3.0 |
| `mcp-bash config` | v0.3.0 |
| `mcp-bash doctor` | v0.3.0 |
| `mcp-bash validate --fix` | v0.3.0 |
| `mcp-bash run-tool` | v0.4.0 |
| `mcp-bash scaffold test` | v0.4.0 |
| Typed helpers (`mcp_args_bool`, `mcp_args_int`, `mcp_args_require`) | v0.4.0 |
| Path helper (`mcp_require_path`) | v0.4.0 |
| Elicitation support (`mcp_elicit`) | v0.3.0 |
| Roots support (`mcp_roots_*`) | v0.3.0 |
| Progress reporting (`mcp_progress`) | v0.2.0 |
| Cancellation (`mcp_is_cancelled`) | v0.2.0 |

---

## Future Considerations

### MCP Registry Submission

The MCP ecosystem is evolving rapidly. Current options for tool discovery:

| Registry | Status | Submission |
|----------|--------|------------|
| **awesome-mcp-servers** (GitHub) | Active community list | Submit PR to add your server |
| **Smithery.ai** | Emerging marketplace | Check their submission process |
| **Glama.ai** | Directory listing | Submit via their site |
| **Official MCP Registry** | Not yet available | Watch modelcontextprotocol.io |

**Preparation checklist**:
- [ ] Clear `server.meta.json` with description and icons
- [ ] Comprehensive tool documentation
- [ ] Stable semantic versioning
- [ ] LICENSE file (MIT recommended)
- [ ] Working installation instructions

### Homebrew/Package Manager Distribution

> **Note**: This is future work. The `mcp-bash-framework` Homebrew formula must be created first before tool formulas can depend on it.

**Planned approach** (not yet implemented):

1. **Phase 1**: Create `homebrew-mcp-bash` tap with framework formula
2. **Phase 2**: Tool formulas can then use `depends_on`:

```ruby
# Future: Homebrew formula (requires framework tap first)
class GitHex < Formula
  depends_on "yaniv-golan/mcp-bash/mcp-bash-framework"
  
  def install
    prefix.install Dir["*"]
  end
end
```

For now, use the one-liner installer or wrapper script approach.

### Multi-Tool Bundles

Multiple related tools can share a repository:
```
devops-mcp-tools/
├── tools/
│   ├── k8s-status/
│   ├── docker-logs/
│   └── aws-describe/
└── server.d/server.meta.json  # name: "devops-tools"
```

---

## Testing git-hex: Comprehensive Strategy

Testing a git-manipulation tool requires **complete isolation** to avoid corrupting real repositories. The key principle: **never run tests against repositories you care about**.

### Testing Layers

| Layer | Purpose | Isolation Level |
|-------|---------|-----------------|
| Unit tests | Test argument parsing, JSON formatting | No git needed |
| Integration tests | Test tool behavior in isolated repos | Temp git repos |
| Destructive tests | Test rebase/amend operations | Disposable clones |
| Security tests | Test path traversal, injection | Sandboxed roots |
| Edge case tests | Test empty repos, detached HEAD, etc. | Temp git repos |

### Test Directory Structure

```
git-hex/
├── test/
│   ├── common/
│   │   ├── assert.sh          # Assertion helpers
│   │   ├── env.sh             # Test environment setup
│   │   └── git_fixtures.sh    # Git repo creation helpers
│   ├── unit/
│   │   ├── run.sh             # Unit test runner
│   │   └── parse_args.bats    # Argument parsing tests
│   ├── integration/
│   │   ├── run.sh             # Integration test runner
│   │   ├── test_get_rebase_plan.sh
│   │   ├── test_perform_rebase.sh
│   │   └── test_create_fixup.sh
│   ├── security/
│   │   ├── run.sh             # Security test runner
│   │   └── test_path_traversal.sh
│   └── run.sh                 # Run all tests
└── .github/
    └── workflows/
        └── test.yml           # CI configuration
```

### Git Fixture Helpers

Create isolated git repositories for each test:

```bash
#!/usr/bin/env bash
# test/common/git_fixtures.sh

# Create a basic git repo with N commits
create_test_repo() {
    local repo_dir="$1"
    local num_commits="${2:-5}"
    
    mkdir -p "${repo_dir}"
    (
        cd "${repo_dir}"
        git init --initial-branch=main
        git config user.email "test@example.com"
        git config user.name "Test User"
        
        for i in $(seq 1 "${num_commits}"); do
            echo "Content ${i}" > "file${i}.txt"
            git add "file${i}.txt"
            # Fixed dates for reproducibility
            GIT_COMMITTER_DATE="2024-01-0${i}T12:00:00" \
            GIT_AUTHOR_DATE="2024-01-0${i}T12:00:00" \
            git commit -m "Commit ${i}"
        done
    )
}

# Create a repo with fixup commits ready for autosquash
create_fixup_scenario() {
    local repo_dir="$1"
    
    mkdir -p "${repo_dir}"
    (
        cd "${repo_dir}"
        git init --initial-branch=main
        git config user.email "test@example.com"
        git config user.name "Test User"
        
        echo "base" > base.txt
        git add base.txt && git commit -m "Initial commit"
        
        echo "feature" > feature.txt
        git add feature.txt && git commit -m "Add feature"
        
        echo "feature fixed" > feature.txt
        git add feature.txt && git commit -m "fixup! Add feature"
        
        echo "another" > another.txt
        git add another.txt && git commit -m "Add another file"
    )
}

# Create a repo with merge conflicts waiting to happen
create_conflict_scenario() {
    local repo_dir="$1"
    
    mkdir -p "${repo_dir}"
    (
        cd "${repo_dir}"
        git init --initial-branch=main
        git config user.email "test@example.com"
        git config user.name "Test User"
        
        echo "line 1" > conflict.txt
        git add conflict.txt && git commit -m "Initial"
        
        echo "line 1 modified by commit 2" > conflict.txt
        git add conflict.txt && git commit -m "Modify in commit 2"
        
        echo "line 1 modified differently" > conflict.txt
        git add conflict.txt && git commit -m "Conflicting modification"
    )
}
```

### Integration Test Example

```bash
#!/usr/bin/env bash
# test/integration/test_get_rebase_plan.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../common/assert.sh"
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_create_tmpdir

# ============================================================
# TEST: get-rebase-plan returns correct structure
# ============================================================
printf ' -> get-rebase-plan returns valid JSON with commits\n'

REPO="${TEST_TMPDIR}/test-repo-1"
create_test_repo "${REPO}" 5

result="$(mcp-bash run-tool gitHex.getRebasePlan \
    --project-root "${MCPBASH_PROJECT_ROOT}" \
    --roots "${REPO}" \
    --args '{"count": 3}' \
    --timeout 30)"

commits_count="$(echo "${result}" | jq -r '.commits | length')"
assert_eq "3" "${commits_count}" "should return 3 commits"

plan_id="$(echo "${result}" | jq -r '.plan_id')"
if [ -z "${plan_id}" ] || [ "${plan_id}" = "null" ]; then
    test_fail "plan_id should be present"
fi

# ============================================================
# TEST: get-rebase-plan fails gracefully on non-git directory
# ============================================================
printf ' -> get-rebase-plan fails on non-git directory\n'

NON_GIT="${TEST_TMPDIR}/not-a-repo"
mkdir -p "${NON_GIT}"

if mcp-bash run-tool gitHex.getRebasePlan \
    --project-root "${MCPBASH_PROJECT_ROOT}" \
    --roots "${NON_GIT}" \
    --args '{}' 2>/dev/null; then
    test_fail "should fail on non-git directory"
fi

printf 'All integration tests passed!\n'
```

### Destructive Operation Test Example

```bash
#!/usr/bin/env bash
# test/integration/test_perform_rebase.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../common/assert.sh"
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_create_tmpdir

# ============================================================
# TEST: perform-rebase aborts cleanly on conflict
# ============================================================
printf ' -> perform-rebase aborts on conflict and restores state\n'

REPO="${TEST_TMPDIR}/rebase-conflict"
create_conflict_scenario "${REPO}"

before_head="$(cd "${REPO}" && git rev-parse HEAD)"

# This should fail but leave repo in clean state
if mcp-bash run-tool gitHex.performRebase \
    --project-root "${MCPBASH_PROJECT_ROOT}" \
    --roots "${REPO}" \
    --args '{"onto": "HEAD~2"}' 2>/dev/null; then
    test_fail "should fail on conflict"
fi

# Verify repo is not in rebase state
if [ -d "${REPO}/.git/rebase-merge" ] || [ -d "${REPO}/.git/rebase-apply" ]; then
    test_fail "repo should not be in rebase state after abort"
fi

# Verify HEAD is restored
after_head="$(cd "${REPO}" && git rev-parse HEAD)"
assert_eq "${before_head}" "${after_head}" "HEAD should be restored after abort"

printf 'All destructive operation tests passed!\n'
```

### Security Test Example

```bash
#!/usr/bin/env bash
# test/security/test_path_traversal.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../common/assert.sh"
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_create_tmpdir

# ============================================================
# SECURITY: Path traversal attempts should be blocked
# ============================================================
printf ' -> blocks path traversal via repoPath\n'

ALLOWED_ROOT="${TEST_TMPDIR}/allowed"
FORBIDDEN_ROOT="${TEST_TMPDIR}/forbidden"

mkdir -p "${ALLOWED_ROOT}"
create_test_repo "${FORBIDDEN_ROOT}" 1

# Try to access forbidden repo via traversal
if mcp-bash run-tool gitHex.getRebasePlan \
    --project-root "${MCPBASH_PROJECT_ROOT}" \
    --roots "${ALLOWED_ROOT}" \
    --args "{\"repoPath\": \"${ALLOWED_ROOT}/../forbidden\"}" 2>/dev/null; then
    test_fail "should block path traversal"
fi

printf 'All security tests passed!\n'
```

### GitHub Actions CI Workflow

```yaml
# .github/workflows/test.yml
name: Test git-hex

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Install mcp-bash framework
        run: |
          curl -fsSL https://raw.githubusercontent.com/yaniv-golan/mcp-bash-framework/main/install.sh | bash
          echo "$HOME/mcp-bash-framework/bin" >> $GITHUB_PATH
      
      - name: Install jq
        run: |
          if [[ "$RUNNER_OS" == "Linux" ]]; then
            sudo apt-get update && sudo apt-get install -y jq
          elif [[ "$RUNNER_OS" == "macOS" ]]; then
            brew install jq
          fi
      
      - name: Validate project
        run: mcp-bash validate
      
      - name: Run unit tests
        run: ./test/unit/run.sh
      
      - name: Run integration tests
        run: ./test/integration/run.sh
      
      - name: Run security tests
        run: ./test/security/run.sh

  test-windows:
    runs-on: windows-latest
    defaults:
      run:
        shell: bash
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Install mcp-bash framework
        run: |
          git clone --depth 1 https://github.com/yaniv-golan/mcp-bash-framework.git ~/mcp-bash-framework
          echo "$HOME/mcp-bash-framework/bin" >> $GITHUB_PATH
      
      - name: Install jq
        run: choco install jq -y
      
      - name: Validate project
        run: mcp-bash validate
      
      - name: Run tests
        run: ./test/integration/run.sh
```

### Key Safety Principles

| Principle | Implementation |
|-----------|----------------|
| **Never test on real repos** | All tests use `TEST_TMPDIR` with auto-cleanup via `trap` |
| **Reproducible state** | Fixed commit dates, deterministic content |
| **Isolation** | Each test creates its own repo |
| **Cleanup on failure** | `trap 'rm -rf "${TEST_TMPDIR}"' EXIT` |
| **No network** | Tests work offline (no remote operations) |
| **Idempotent** | Running tests twice produces same result |

### Running Tests Locally

```bash
# Run all tests
./test/run.sh

# Run specific test suite
./test/integration/run.sh

# Run with verbose output
VERBOSE=1 ./test/integration/run.sh

# Run single test file
./test/integration/test_get_rebase_plan.sh
```

---

## References

- **mcp-bash Framework**: <https://github.com/yaniv-golan/mcp-bash-framework>
- **MCP Specification**: <https://spec.modelcontextprotocol.io/>
- **Project Structure Guide** (framework repo):  
  <https://github.com/yaniv-golan/mcp-bash-framework/blob/main/docs/PROJECT-STRUCTURE.md>
- **Tool SDK Reference** (framework repo):  
  <https://github.com/yaniv-golan/mcp-bash-framework/blob/main/sdk/tool-sdk.sh>
