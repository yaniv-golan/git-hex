# Proposal: Tool Policy Hook for mcp-bash-framework

**Status**: Implemented  
**Author**: git-hex project  
**Date**: 2025-12-06

> **Note**: This proposal has been implemented in mcp-bash-framework. See `lib/tools_policy.sh` in the framework and `server.d/policy.sh` in git-hex for the actual implementation.

## Summary

Add a pre-execution policy hook to mcp-bash-framework that allows projects to gate tool invocations based on custom logic. This enables use cases like read-only modes, tool allowlists, audit logging, and rate limiting without requiring per-tool code changes.

## Motivation

### Problem

Projects built on mcp-bash may need to restrict which tools can be executed based on runtime configuration. Current options are:

1. **Check in each tool** - Repetitive, error-prone, must remember to add to new tools
2. **No restriction** - All tools always available

### Use Cases

1. **Read-only mode**: Disable mutating tools while keeping inspection tools available
   - Example: `GIT_HEX_READ_ONLY=1` disables `performRebase`, `amendLastCommit`, etc.
   
2. **Tool allowlists**: Only permit specific tools in restricted environments
   - Example: `MYPROJECT_ALLOWED_TOOLS="tool1,tool2,tool3"`

3. **Audit logging**: Log all tool invocations before execution
   - Example: Write to audit log with tool name, args, timestamp, caller

4. **Rate limiting**: Prevent runaway tool invocations
   - Example: Max 100 tool calls per minute

5. **Capability-based access**: Gate tools based on client capabilities or auth
   - Example: Only allow destructive tools if client passed capability check

## Proposed Design

### Core Hook

Add a `mcp_tools_policy_check` function that's called before every tool execution:

```bash
# lib/tools.sh, inside mcp_tools_call(), before execution:

# Check tool-level policy (projects can override in server.d/policy.sh)
if ! mcp_tools_policy_check "${name}" "${metadata}"; then
    # Policy check sets error via mcp_tools_error
    return 1
fi
```

### Default Implementation

The framework provides a permissive default:

```bash
# lib/tools_policy.sh (or extend lib/policy.sh)

# Tool execution policy hook.
# Called before every tool invocation.
# 
# Arguments:
#   $1 - tool name (e.g., "gitHex.performRebase")
#   $2 - tool metadata JSON (name, path, inputSchema, etc.)
#
# Returns:
#   0 - allow execution
#   1 - deny execution (must call mcp_tools_error first)
#
# Projects override by defining mcp_tools_policy_check in server.d/policy.sh
mcp_tools_policy_check() {
    # Default: allow all tools
    return 0
}
```

### Project Override

Projects provide their own implementation in `server.d/policy.sh`:

```bash
#!/usr/bin/env bash
# server.d/policy.sh - Tool execution policy for git-hex

mcp_tools_policy_check() {
    local tool_name="$1"
    local metadata="$2"  # Available if needed for schema-based decisions
    
    # Read-only mode: only allow inspection tools
    if [ "${GIT_HEX_READ_ONLY:-}" = "1" ]; then
        case "${tool_name}" in
            gitHex.getRebasePlan)
                return 0  # Inspection tool - allowed
                ;;
            *)
                mcp_tools_error -32602 "git-hex is running in read-only mode. Tool '${tool_name}' is disabled."
                return 1
                ;;
        esac
    fi
    
    # Default: allow
    return 0
}
```

### Loading Order

The framework already sources `server.d/*.sh` files. The policy hook would be:

1. Framework defines default `mcp_tools_policy_check` in `lib/tools_policy.sh`
2. Project's `server.d/policy.sh` (if present) overrides the function
3. `mcp_tools_call` invokes whatever implementation is active

## API

### Function Signature

```bash
mcp_tools_policy_check <tool_name> <metadata_json>
```

### Arguments

| Argument | Type | Description |
|----------|------|-------------|
| `tool_name` | string | The tool being invoked (e.g., `"gitHex.performRebase"`) |
| `metadata_json` | JSON string | Tool metadata including `name`, `path`, `inputSchema`, `timeoutSecs` |

### Return Value

| Return | Meaning |
|--------|---------|
| `0` | Allow execution |
| `1` | Deny execution (must call `mcp_tools_error` before returning) |

### Error Reporting

When denying, the policy function MUST call `mcp_tools_error` before returning:

```bash
mcp_tools_error -32602 "Descriptive error message"
return 1
```

Recommended error codes:
- `-32602` (Invalid params) - For policy violations like read-only mode
- `-32600` (Invalid request) - For capability/auth failures

## Examples

### Example 1: Simple Read-Only Mode

```bash
# server.d/policy.sh
mcp_tools_policy_check() {
    local tool_name="$1"
    
    if [ "${MYPROJECT_READ_ONLY:-}" = "1" ]; then
        # Allowlist of read-only tools
        case "${tool_name}" in
            myProject.list*|myProject.get*|myProject.describe*)
                return 0
                ;;
            *)
                mcp_tools_error -32602 "Read-only mode: '${tool_name}' is disabled"
                return 1
                ;;
        esac
    fi
    return 0
}
```

### Example 2: Tool Allowlist

```bash
# server.d/policy.sh
mcp_tools_policy_check() {
    local tool_name="$1"
    local allowed="${MYPROJECT_ALLOWED_TOOLS:-}"
    
    if [ -n "${allowed}" ]; then
        # Check if tool is in comma-separated allowlist
        if ! echo ",${allowed}," | grep -q ",${tool_name},"; then
            mcp_tools_error -32602 "Tool '${tool_name}' is not in the allowed list"
            return 1
        fi
    fi
    return 0
}
```

### Example 3: Audit Logging

```bash
# server.d/policy.sh
mcp_tools_policy_check() {
    local tool_name="$1"
    
    # Log all tool invocations (allow all, just log)
    if [ -n "${MYPROJECT_AUDIT_LOG:-}" ]; then
        printf '%s tool_invocation tool=%s\n' "$(date -Iseconds)" "${tool_name}" >> "${MYPROJECT_AUDIT_LOG}"
    fi
    
    return 0
}
```

### Example 4: Metadata-Based Policy

```bash
# server.d/policy.sh
mcp_tools_policy_check() {
    local tool_name="$1"
    local metadata="$2"
    
    # Deny tools with timeout > 60 seconds in restricted mode
    if [ "${MYPROJECT_RESTRICTED:-}" = "1" ]; then
        local timeout
        timeout="$(printf '%s' "${metadata}" | jq -r '.timeoutSecs // 30')"
        if [ "${timeout}" -gt 60 ]; then
            mcp_tools_error -32602 "Tool '${tool_name}' exceeds max timeout in restricted mode"
            return 1
        fi
    fi
    return 0
}
```

## Implementation Notes

### Framework Changes Required

1. **New file**: `lib/tools_policy.sh` with default implementation
2. **Modify**: `lib/tools.sh` to source policy and call hook in `mcp_tools_call`
3. **Modify**: `bin/mcp-bash` to include `tools_policy` in required libs
4. **Document**: Update docs with policy hook usage

### Minimal Diff to lib/tools.sh

```diff
 mcp_tools_call() {
     local name="$1"
     local args_json="$2"
     local timeout_override="$3"
     
     # ... existing setup code ...
     
     local metadata
     if ! metadata="$(mcp_tools_metadata_for_name "${name}")"; then
         mcp_tools_error -32601 "Tool not found"
         return 1
     fi
+    
+    # Check tool-level policy before execution
+    if ! mcp_tools_policy_check "${name}" "${metadata}"; then
+        return 1
+    fi
     
     local tool_path metadata_timeout output_schema
     # ... rest of function ...
```

### Backwards Compatibility

- **Fully backwards compatible**: Default implementation allows all tools
- **No breaking changes**: Existing projects continue to work unchanged
- **Opt-in**: Projects add `server.d/policy.sh` only if they need policy control

## Alternatives Considered

### 1. Per-Tool Checks

Each tool checks its own policy:

```bash
# In each mutating tool
if [ "${GIT_HEX_READ_ONLY:-}" = "1" ]; then
    mcp_fail_invalid_args "Read-only mode"
fi
```

**Rejected because**: Repetitive, error-prone, doesn't scale, must remember for new tools.

### 2. Tool Metadata Flags

Add `readOnly: true` to tool.meta.json and let framework filter:

```json
{
  "name": "gitHex.getRebasePlan",
  "readOnly": true
}
```

**Rejected because**: Less flexible, can't handle dynamic policies, requires schema changes.

### 3. Separate Policy Config File

A JSON/YAML policy configuration:

```yaml
policies:
  - match: "gitHex.*"
    deny_when: "env.GIT_HEX_READ_ONLY == '1'"
    except: ["gitHex.getRebasePlan"]
```

**Rejected because**: Over-engineered, requires parser, less flexible than code.

## Open Questions

1. **Should metadata be passed?** Yes - enables schema-based policies without re-parsing.

2. **Should args be passed?** No - policy should be tool-level, not invocation-level. Arg validation belongs in the tool itself.

3. **Should there be a post-execution hook?** Out of scope for this proposal, but could be added later for audit/metrics.

4. **File naming**: `server.d/policy.sh` vs `server.d/tools_policy.sh`? Recommend `policy.sh` for simplicity since it's the only policy file currently.

## References

- [GitHub MCP Server --toolsets](https://github.com/github/github-mcp-server) - Similar concept with CLI flags
- [mcp-bash lib/policy.sh](https://github.com/yaniv-golan/mcp-bash-framework/blob/main/lib/policy.sh) - Existing host-level policy
- [git-hex read-only discussion](./proposal-tool-policy-hook.md) - Original motivation

