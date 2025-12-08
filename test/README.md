# Testing git-hex

This directory contains tests for the git-hex MCP server.

## Prerequisites

The tests require the `mcp-bash` framework. You can either:

1. **Install the framework** (recommended for CI):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/yaniv-golan/mcp-bash-framework/main/install.sh | bash -s -- --yes --version v0.6.0
   ```

2. **Use a local development version** by setting `MCPBASH_HOME`:
   ```bash
   export MCPBASH_HOME=$HOME/.local/share/mcp-bash
   ```

The test harness auto-detects sibling directories (e.g., `../mcpbash`) for local development.

## Running Tests

Run all tests:
```bash
./test/run.sh
```

Run only integration tests:
```bash
./test/integration/run.sh
```

Run only security tests:
```bash
./test/security/run.sh
```

Run lint (shellcheck + shfmt):
```bash
./test/lint.sh
```

### Runner flags

- `VERBOSE=1` streams per-test logs (instead of only printing on failure).
- `UNICODE=1` uses ✅/❌ status icons.
- `GITHEX_INTEGRATION_TMP=/tmp/githex` writes integration logs to a fixed dir (useful for CI).
- `KEEP_INTEGRATION_LOGS=1` keeps logs even on success (default removes them on success).

Enable the provided pre-commit hook to auto-run lint before commits:
```bash
git config core.hooksPath .githooks
```
Or install pre-commit to reuse the same hook configuration:
```bash
pre-commit install
```

## Test Structure

```
test/
├── run.sh                    # Main test runner (runs all suites)
├── common/
│   ├── env.sh               # Test environment setup
│   ├── assert.sh            # Assertion helpers
│   └── git_fixtures.sh      # Git repository fixtures
├── integration/
│   ├── run.sh               # Integration test runner
│   └── test_*.sh            # Individual integration tests
└── security/
    ├── run.sh               # Security test runner
    └── test_*.sh            # Security/path traversal tests
```

## Writing Tests

### Integration Tests

Create a new file `test/integration/test_my_feature.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Source test helpers
source "$(dirname "${BASH_SOURCE[0]}")/../common/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/assert.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common/git_fixtures.sh"

test_create_tmpdir
test_verify_framework

echo "=== Testing my feature ==="

# Create a test repo
repo="${TEST_TMPDIR}/my-repo"
create_test_repo "${repo}" 5

# Run tool and check result
result="$(run_tool "git-hex-myTool" "${repo}" '{"arg": "value"}')"
assert_json_field "${result}" ".success" "true"

echo "All tests passed!"
```

### Using Test Helpers

**`run_tool`** - Run a tool and get structured output:
```bash
result="$(run_tool "git-hex-getRebasePlan" "${repo}" '{"count": 5}')"
```

**`run_tool_expect_fail`** - Expect a tool to fail:
```bash
if run_tool_expect_fail "git-hex-getRebasePlan" "/nonexistent" '{}'; then
    echo "PASS: correctly rejected invalid path"
fi
```

**Git fixtures** - Create test repositories:
```bash
create_test_repo "${repo}" 5           # 5 commits
create_fixup_scenario "${repo}"        # Repo with fixup commits
create_conflict_scenario "${repo}"     # Repo with conflict setup
```

### Assertions

```bash
assert_eq "actual" "expected" "description"
assert_json_field "${json}" ".field" "expected_value"
```

## Testing with mcp-bash run-tool

For manual testing or debugging:

```bash
# Test a tool directly
mcp-bash run-tool git-hex-getRebasePlan \
    --args '{"repoPath": "/path/to/repo", "count": 5}' \
    --roots '/path/to/repo'

# With custom timeout
mcp-bash run-tool git-hex-rebaseWithPlan \
    --args '{"onto": "main"}' \
    --roots '/path/to/repo' \
    --timeout 120
```

> **Windows/Git Bash Note**: Set `MSYS2_ARG_CONV_EXCL="*"` before running commands with path arguments to prevent automatic path mangling.

## CI Integration

See `.github/workflows/test.yml` for the GitHub Actions configuration. The CI:
1. Installs the mcp-bash framework (pinned to v0.6.0).
2. Runs lint on Linux (shellcheck + shfmt).
3. Runs `mcp-bash validate`, integration tests, and security tests on Linux and macOS (with failure logs artifacted).
4. Runs integration tests on Windows with a time budget guard.
5. Runs a scheduled weekly full suite on Ubuntu.

CI runs with `MCPBASH_CI_MODE`, `MCPBASH_CI_VERBOSE`, and `MCPBASH_TRACE_TOOLS` enabled to capture env snapshots, failure summaries, and per-tool traces into `$MCPBASH_LOG_DIR` for easier debugging.

## Reference

- [mcp-bash Best Practices](https://github.com/yaniv-golan/mcp-bash-framework/blob/main/docs/BEST-PRACTICES.md)
- [run-tool CLI Reference](https://github.com/yaniv-golan/mcp-bash-framework/blob/main/docs/BEST-PRACTICES.md#testing-tools-with-run-tool)
