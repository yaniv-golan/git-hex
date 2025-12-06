# Contributing to git-hex

Thank you for your interest in contributing to git-hex! This document provides guidelines and instructions for contributing.

## Getting Started

### Prerequisites

- **bash** 3.2+
- **jq** or **gojq**
- **git** 2.20+ (2.33+ recommended)
- **mcp-bash framework** v0.4.0+

### Setup

```bash
# Clone the repository
git clone https://github.com/yaniv-golan/git-hex.git
cd git-hex

# Install the mcp-bash framework (if not already installed)
curl -fsSL https://raw.githubusercontent.com/yaniv-golan/mcp-bash-framework/main/install.sh | bash

# Verify setup
./run.sh  # Should start without errors (Ctrl+C to exit)
```

## Development Workflow

### Project Structure

```
git-hex/
├── tools/                    # MCP tools (one directory per tool)
│   ├── amend-last-commit/
│   │   ├── tool.meta.json    # Tool schema and metadata
│   │   └── tool.sh           # Tool implementation
│   └── ...
├── lib/                      # Shared bash libraries
├── test/
│   ├── integration/          # Integration tests (test_*.sh)
│   ├── security/             # Security tests
│   └── common/               # Test helpers
└── run.sh                    # Wrapper script
```

### Adding a New Tool

1. Create a new directory under `tools/`:
   ```bash
   mkdir -p tools/my-new-tool
   ```

2. Create `tool.meta.json` with the tool schema:
   ```json
   {
     "name": "gitHex.myNewTool",
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
       "required": ["success"],
       "properties": {
         "success": { "type": "boolean" }
       }
     }
   }
   ```

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
   
   mcp_emit_json '{"success": true}'
   ```

4. Make it executable:
   ```bash
   chmod +x tools/my-new-tool/tool.sh
   ```

### Tool Naming Convention

- Tool names use camelCase with `gitHex.` prefix: `gitHex.myNewTool`
- Directory names use kebab-case: `my-new-tool`

### API Conventions

All tools should follow these output conventions:

- **`success`**: boolean, always present
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
mcp-bash validate
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

echo "=== Testing gitHex.myNewTool ==="

# Create test repo
REPO="${TEST_TMPDIR}/test-repo"
create_test_repo "${REPO}" 3

# Run tool
result="$(run_tool gitHex.myNewTool "${REPO}" '{}')"

# Assert results
assert_json_field "${result}" '.success' "true" "should succeed"

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

- Use tabs for indentation (enforced by `.editorconfig`)
- Use `local` for function-scoped variables
- Quote all variable expansions: `"${var}"` not `$var`
- Use `[[ ]]` for conditionals, not `[ ]`
- Use `printf` over `echo` for output
- Use `$(...)` for command substitution, not backticks

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
feat: add gitHex.squashCommits tool

Adds a new tool for squashing a range of commits into one.
Includes backup ref support for undo functionality.
```

## Questions?

Open an issue on GitHub if you have questions or need help.
