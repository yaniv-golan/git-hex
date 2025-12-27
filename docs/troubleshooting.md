# Troubleshooting

This guide helps diagnose and fix common issues with git-hex, especially MCP client connection problems.

## Quick Diagnostic Steps

```bash
# 1. Validate installation and metadata
./git-hex.sh validate

# 2. Test with strict client validation (requires Node.js)
./git-hex.sh validate --inspector

# 3. Check framework health
./git-hex.sh doctor
```

---

## Common Issues

### "Client closed for command" / "Connection Error" in Cursor

**Symptoms:**
- git-hex works from command line but not in Cursor
- Cursor shows "Client closed for command" error
- MCP Inspector shows "Connection Error"

**Diagnosis:**
```bash
# Test with MCP Inspector CLI (catches strict validation errors)
npx @modelcontextprotocol/inspector --cli --transport stdio -- \
  ./git-hex-env.sh --method tools/list
```

If this shows a validation error like:
```
serverInfo.icons[0] - expected object, received string
```

**Fix:** Update `server.d/server.meta.json` icons format:
```json
// Wrong
"icons": ["path/to/icon.svg"]

// Correct
"icons": [{"src": "path/to/icon.svg"}]
```

### Server works in CLI but not in Cursor/Claude Desktop

**Common causes:**

1. **PATH not available in GUI apps**
   - GUI apps don't source your shell profile
   - Use `git-hex-env.sh` (not `git-hex.sh`) which handles this

2. **macOS quarantine**
   ```bash
   # Check for quarantine attributes
   xattr -l ~/.local/share/mcp-bash/bin/mcp-bash

   # Remove quarantine if present
   xattr -r -d com.apple.quarantine ~/.local/share/mcp-bash
   ```

3. **TCC-protected folders** (macOS)
   - Documents/Desktop/Downloads require special permissions
   - Grant Cursor "Full Disk Access" in System Settings, or move git-hex elsewhere

### Framework not found

**Symptom:**
```
Error: mcp-bash not found
```

**Fix:**
```bash
./git-hex.sh install
```

### Framework version too old

**Symptom:**
```
Error: mcp-bash X.Y.Z found, but git-hex requires vA.B.C+
```

**Fix:**
```bash
./git-hex.sh install
```

---

## Debugging with Logs

### Enable debug logging

Use the `debug` subcommand to capture all JSON-RPC messages:

```bash
# Test with debug logging
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{...}}' | \
  ./git-hex-env.sh debug
```

The log location is printed at startup:
```
mcp-bash debug: logging to /tmp/mcpbash.debug.XXXXX/payload.debug.log
```

### Analyze debug logs

```bash
# View all messages
cat /tmp/mcpbash.debug.XXXXX/payload.debug.log

# Pretty-print with jq
cut -d'|' -f5 /tmp/mcpbash.debug.XXXXX/payload.debug.log | jq .

# Find errors
grep -E '\|error\|' /tmp/mcpbash.debug.XXXXX/payload.debug.log
```

### Using MCP Inspector

For detailed protocol-level debugging, use MCP Inspector:

```bash
# Get ready-to-run Inspector command
./git-hex-env.sh config --inspector

# Or run directly
npx @modelcontextprotocol/inspector -e MCPBASH_PROJECT_ROOT=$(pwd) \
  --transport stdio -- ./git-hex-env.sh
```

---

## Cursor-Specific Setup

### Verify MCP configuration

Check `.cursor/mcp.json` in your project:
```json
{
  "mcpServers": {
    "git-hex": {
      "command": "/path/to/git-hex/git-hex-env.sh"
    }
  }
}
```

**Important:** Use `git-hex-env.sh` (not `git-hex.sh`) for Cursor. The `-env` launcher handles shell profile sourcing for GUI apps.

### Test before opening Cursor

```bash
# Validate everything works
./git-hex.sh validate --inspector

# If this passes, restart Cursor to pick up the MCP server
```

### Restart Cursor after changes

After modifying `mcp.json` or fixing issues, you must restart Cursor:
1. Close all Cursor windows
2. Reopen Cursor
3. Check MCP server status in Cursor settings

---

## Claude Desktop Setup

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "git-hex": {
      "command": "/path/to/git-hex/git-hex-env.sh"
    }
  }
}
```

Then restart Claude Desktop.

---

## Getting Help

If you're still stuck:

1. Run full diagnostics:
   ```bash
   ./git-hex.sh validate --inspector 2>&1 | tee git-hex-debug.log
   ./git-hex.sh doctor 2>&1 | tee -a git-hex-debug.log
   ```

2. Open an issue at https://github.com/yaniv-golan/git-hex/issues with:
   - The `git-hex-debug.log` output
   - Your OS and shell version
   - Which MCP client you're using (Cursor, Claude Desktop, etc.)
