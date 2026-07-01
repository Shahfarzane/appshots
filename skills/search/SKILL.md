---
name: search
description: Search past appshots by app name, window title, URL, or captured text
---

# Search AppShots

Use when you need to find a specific earlier capture by searching app name, window title, browser URL, or on-screen text content.

## When to use

- User asks to "find the screenshot of [thing]" or "where did we capture that"
- You need to revisit a past capture from minutes or hours ago
- Searching by window title: "find the Settings window"
- Searching by app: "show me all Chrome captures"
- Searching by URL: "find the GitHub issue we were looking at"
- Searching by text: "find the capture with 'error 404'"

## What it does

Invokes the `search_appshots` MCP tool, which searches the indexed appshot history (`~/.appshots/index.json`):

1. Queries app executable name, window title, page URL, and accessibility tree text
2. Returns up to 20 matches (configurable limit) sorted by recency
3. Each result includes capture metadata: app, title, URL, timestamp, capture directory path
4. Lets you load a specific capture without a fresh screenshot

## Parameters

- `query` (required): search term(s) — app name, window title, URL fragment, or on-screen text
- `limit` (optional): number of results to return, default 20, min 1, max 100

## Output

Returns a JSON array of matching captures, each with:
- `id`: unique capture identifier
- `app`: application name and bundle identifier
- `title`: window title
- `url`: page URL if a browser was captured
- `timestamp`: capture time
- `path`: directory path to access the full capture

## Related

- [`get_latest_appshot`](/appshots:latest) — fetch the most recent capture directly
- [`take_appshot`](/appshots:capture) — capture the current window right now
- [`list_appshots`](/appshots:list) — browse recent captures without searching
