# Testing git-hex

This directory contains tests for the git-hex MCP server.

## Prerequisites

The tests require the `mcp-bash` framework. You can either:

1. **Install the framework** (recommended for CI):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/yaniv-golan/mcp-bash-framework/main/install.sh | bash -s -- --yes
   ```

2. **Use a local development version** by setting `MCPBASH_HOME`:
   ```bash
   export MCPBASH_HOME=/path/to/mcp-bash-framework
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
result="$(run_tool "gitHex.myTool" "${repo}" '{"arg": "value"}')"
assert_json_field "${result}" ".success" "true"

echo "All tests passed!"
```

### Using Test Helpers

**`run_tool`** - Run a tool and get structured output:
```bash
result="$(run_tool "gitHex.getRebasePlan" "${repo}" '{"count": 5}')"
```

**`run_tool_expect_fail`** - Expect a tool to fail:
```bash
if run_tool_expect_fail "gitHex.getRebasePlan" "/nonexistent" '{}'; then
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
mcp-bash run-tool gitHex.getRebasePlan \
    --args '{"repoPath": "/path/to/repo", "count": 5}' \
    --roots '/path/to/repo'

# With custom timeout
mcp-bash run-tool gitHex.performRebase \
    --args '{"onto": "main"}' \
    --roots '/path/to/repo' \
    --timeout 120
```

> **Windows/Git Bash Note**: Set `MSYS2_ARG_CONV_EXCL="*"` before running commands with path arguments to prevent automatic path mangling.

## CI Integration

See `.github/workflows/test.yml` for the GitHub Actions configuration. The CI:
1. Installs the mcp-bash framework (pinned to v0.4.0)
2. Runs `mcp-bash validate` to check project structure
3. Runs integration and security tests

## Reference

- [mcp-bash Best Practices](https://github.com/yaniv-golan/mcp-bash-framework/blob/main/docs/BEST-PRACTICES.md)
- [run-tool CLI Reference](https://github.com/yaniv-golan/mcp-bash-framework/blob/main/docs/BEST-PRACTICES.md#testing-tools-with-run-tool)
