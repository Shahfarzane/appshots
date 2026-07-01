# Appshots

Use Appshots when the user has captured a macOS application window and wants you to inspect the same visual and accessibility context.

> **Note:** The Claude Code plugin under `.claude-plugin/` (with the skills in `skills/` and the MCP server wired through `bin/appshotsctl`) supersedes the manual setup below. Install it with `/plugin marketplace add Shahfarzane/appshots` then `/plugin install appshots`, and the MCP server registers automatically. This file remains valid for shell-only / non-plugin agents.

## Fast Path

1. Read the latest appshot prompt:

   ```sh
   cat ~/.appshots/latest.md
   ```

2. Read the latest capture directory:

   ```sh
   cat ~/.appshots/latest.txt
   ```

3. Use files in that directory as needed:

   - `screenshot.png` for visual inspection.
   - `accessibility_tree.txt` for prompt-ready UI text.
   - `accessibility_tree.json` for structured node data.
   - `page_url.txt` when a browser URL was captured.
   - `metadata.json` for app/window/capture metadata.
   - `transition-snapshot.png` is a polished preview for Appshots' own capture animation, not for inspection — use `screenshot.png` instead.

## CLI

```sh
appshotsctl capture
appshotsctl latest
appshotsctl latest --image
appshotsctl latest --json
appshotsctl list
appshotsctl search "settings"
appshotsctl doctor
```

If `appshotsctl` is not installed globally, use the repo build output:

```sh
/Users/shahin/Code/Github/appshots/.build/debug/appshotsctl latest
```

## MCP

Register the native MCP server (built into `appshotsctl`) with Claude Code:

```sh
claude mcp add appshots -s user -- /Users/shahin/Code/Github/appshots/.build/debug/appshotsctl mcp
```

Available tools:

- `take_appshot`
- `get_latest_appshot`
- `get_appshot_image`
- `list_appshots`
- `search_appshots`
- `delete_appshot`
- `doctor_appshots`
