---
name: list
description: List recent appshots with metadata
---

# List AppShots

Use when you want to browse the history of recent app captures without searching or taking a fresh screenshot.

## When to use

- User asks for "recent captures", "what did we screenshot", or "show me the history"
- You want to explore available past captures before searching
- Checking how many appshots exist and their timestamps
- Building a menu or context of available captures for the user to choose from

## What it does

Invokes the `list_appshots` MCP tool, which returns recent captures from the appshot history:

1. Reads the capture index (`~/.appshots/index.json`)
2. Returns the N most recent captures in reverse chronological order (newest first)
3. Includes metadata for each: app name, window title, URL (if browser), timestamp, and path
4. Results are JSON for easy parsing and display

## Parameters

- `limit` (optional): number of recent captures to return, default 20, min 1, max 100

## Output

Returns a JSON array of serialized capture records; the key fields:
- `id`: unique capture identifier
- `appName` / `bundleID`: the captured application
- `windowTitle`: window title
- `pageURL`: page URL if a browser capture
- `createdAt`: when the capture was taken (ISO 8601)
- `directoryPath`: directory path to access the full capture

## Related

- [`search_appshots`](/appshots:search) — find captures matching a query
- [`get_latest_appshot`](/appshots:latest) — get the single most recent capture
- [`take_appshot`](/appshots:capture) — capture the current window now
