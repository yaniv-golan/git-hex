# Contributing to git-hex

Thank you for your interest in contributing to git-hex! This document provides guidelines and instructions for contributing.

## Getting Started

### Prerequisites

- **bash** 3.2+
- **jq** or **gojq**
- **git** 2.20+ (2.33+ recommended; 2.38+ required for `git-hex-checkRebaseConflicts`)
- **mcp-bash** installed on your system (`brew install yaniv-golan/mcp-bash/mcp-bash`) for `doctor`, `validate`, `run-tool` and the tests. The server itself runs on the runtime vendored in `.mcp-bash/`.

### Setup

```bash
# Clone the repository
git clone https://github.com/yaniv-golan/git-hex.git
cd git-hex

# Verify setup
./git-hex.sh doctor
```

> **Framework Version:** the server runs on the mcp-bash runtime vendored in `.mcp-bash/` (version and checksum in `.mcp-bash/vendor.json`). To upgrade it, run `make vendor-upgrade` with the new mcp-bash installed, then `make vendor-verify`, and commit `.mcp-bash/`. Keep `FRAMEWORK_VERSION` and `FRAMEWORK_SHA256` in the `Dockerfile` at the same version.

> Note: mcp-bash-framework v0.7.0+ requires tool allowlisting. The `./git-hex.sh` and `./git-hex-env.sh` launchers set `MCPBASH_TOOL_ALLOWLIST` to the explicit git-hex tool set (and narrow it further in read-only mode) so tools can run safely.
>
> Completions are registered declaratively via `server.d/register.json` (no hook enable required).

## Development Workflow

### Project Structure

```
git-hex/
├── tools/                    # MCP tools (one directory per tool)
│   ├── git-hex-amendLastCommit/
│   │   ├── tool.meta.json    # Tool schema and metadata
│   │   └── tool.sh           # Tool implementation
│   └── ...
├── lib/                      # Shared bash libraries
├── test/
│   ├── integration/          # Integration tests (test_*.sh)
│   ├── security/             # Security tests
│   └── common/               # Test helpers
└── git-hex.sh                # Wrapper script
```

### Adding a New Tool

1. Create a new directory under `tools/`:
   ```bash
   mkdir -p tools/git-hex-myNewTool
   ```

2. Create `tool.meta.json` with the tool schema:
   ```json
   {
     "name": "git-hex-myNewTool",
     "description": "What this tool does",
     "inputSchema": {
       "type": "object",
       "properties": {
         "repoPath": {
           "type": "string",
           "description": "Path to git repository"
         }
       }
     },
     "outputSchema": {
       "type": "object",
       "required": ["summary"],
       "properties": {
         "summary": { "type": "string", "description": "Human-readable explanation" }
       }
     }
   }
   ```

   > **Note:** The `outputSchema` describes the result object the tool emits with `mcp_result_json`; there is no `{success, result}` envelope.

3. Create `tool.sh` with the implementation:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail

   source "${MCP_SDK:?}/tool-sdk.sh"

   # Source backup helper for undo support (if mutating)
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
   source "${SCRIPT_DIR}/../../lib/backup.sh"

   # Parse arguments
   repo_path="$(mcp_require_path '.repoPath' --default-to-single-root)"

   # Your implementation here...

   # Build and emit the result
   result="$("${MCPBASH_JSON_TOOL_BIN}" -n --arg summary "Operation completed" '{summary: $summary}')"
   mcp_result_json "${result}"
   ```

4. Make it executable:
   ```bash
   chmod +x tools/git-hex-myNewTool/tool.sh
   ```

### Tool Naming Convention

- Tool names use camelCase with `git-hex-` prefix: `git-hex-myNewTool`
- Tool directory names match the tool name: `tools/git-hex-myNewTool/`

### API Conventions

Tools emit their result object with `mcp_result_json`, and report errors with `git_hex_error CODE "message" ["suggestion" ...]` (from `lib/git-helpers.sh`), which ends the tool with an `isError` result:

```bash
result="$("${MCPBASH_JSON_TOOL_BIN}" -n \
    --arg headBefore "${head_before}" \
    --arg headAfter "${head_after}" \
    --arg summary "Operation completed" \
    '{headBefore: $headBefore, headAfter: $headAfter, summary: $summary}')"
mcp_result_json "${result}"
```

Common result fields:
- **`headBefore`**: commit hash before operation (for mutating tools)
- **`headAfter`**: commit hash after operation (for mutating tools)
- **`summary`**: human-readable explanation of what happened
- **`commitMessage`**: git commit subject line (when returning commit info)

For mutating tools, create a backup ref before making changes:
```bash
git_hex_create_backup "${repo_path}" "myNewTool" >/dev/null
```

## Testing

### Running Tests

```bash
# Run all integration tests
./test/integration/run.sh

# Run lint (shellcheck + shfmt)
./test/lint.sh

# Run a specific test
./test/integration/test_amend_last_commit.sh

# Run security tests
./test/security/run.sh

# Validate project structure
./git-hex.sh validate
```

### Pre-commit Hook (optional but recommended)

Enable the repo-provided hook to auto-run lint before commits:

```bash
git config core.hooksPath .githooks
```

### Writing Tests

Create test files in `test/integration/` named `test_<tool-name>.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "${SCRIPT_DIR}/../common/env.sh"
. "${SCRIPT_DIR}/../common/assert.sh"
. "${SCRIPT_DIR}/../common/git_fixtures.sh"

test_verify_framework
test_create_tmpdir

echo "=== Testing git-hex-myNewTool ==="

# Create test repo
REPO="${TEST_TMPDIR}/test-repo"
create_test_repo "${REPO}" 3

# Run tool (prints the structured result; fails with {type, message} on an isError result)
result="$(run_tool git-hex-myNewTool "${REPO}" '{}')"

# Assert results
assert_json_field "${result}" '.summary' "Operation completed" "should have summary"

test_pass "my-new-tool works"
```

### Test Helpers

- `create_test_repo <path> <num_commits>` - Create a repo with N commits
- `create_staged_changes_repo <path>` - Create a repo with staged changes
- `create_branch_scenario <path>` - Create a repo with main + feature branch
- `run_tool <name> <roots> <args>` - Run a tool and get JSON output
- `run_tool_expect_fail <name> <roots> <args>` - Expect tool to fail
- `assert_json_field <json> <jq-path> <expected> <message>` - Assert JSON field value
- `assert_eq <expected> <actual> <message>` - Assert equality

## Code Style

- Use tabs for indentation in shell scripts (see `.editorconfig`)
- Use `local` for function-scoped variables
- Quote all variable expansions: `"${var}"` not `$var`
- Prefer `[[ ]]` for bash conditionals; match the surrounding style when modifying existing files
- Use `printf` over `echo` for output
- Use `$(...)` for command substitution, not backticks

## Documentation style

- When writing user-facing docs, prefer “allowed folders” and introduce the MCP term once: “allowed folders (MCP `roots`)”. See `docs/concepts.md`.
- Avoid “login shell” jargon in user-facing docs. Prefer “macOS apps launched from Finder/Spotlight/Dock” and link to `docs/clients.md`.

## Submitting Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run tests: `./test/integration/run.sh`
5. Commit with a descriptive message
6. Push and open a Pull Request

### Commit Message Format

```
<type>: <short description>

<optional longer description>
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`

Example:
```
feat: add git-hex-rebaseWithPlan improvements

Adds structured plan validation and better conflict handling for rebases.
Includes backup ref support for undo functionality.
```

## Questions?

Open an issue on GitHub if you have questions or need help.
