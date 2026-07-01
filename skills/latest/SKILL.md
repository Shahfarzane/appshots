---
name: latest
description: Fetch the most recent appshot without taking a new capture
---

# Get Latest AppShot

Use when you need to reference the most recent app capture without initiating a fresh screenshot.

## When to use

- User shows you something and you want to access the last appshot they captured
- You're analyzing or building on a previous capture from the same session
- You need to compare current state to the cached latest appshot
- User asks to "show me the latest", "get the last screenshot", or "what did we capture"

## What it does

Invokes the `get_latest_appshot` MCP tool, which retrieves the most recent capture from `~/.appshots/`:

1. Reads the stable pointer `~/.appshots/latest.txt` to get the capture directory
2. Loads the appshot prompt, screenshot, accessibility tree, and metadata
3. Returns in the requested format (default: the full appshot markdown text)

## Output formats

Pass `format` to customize the response:

- `prompt` (default): the full appshot markdown with Codex `<appshot>` block
- `codex`: `<appshot>` block + screenshot image for model input
- `model_prompt`: model-ready prompt format
- `context`: structured `AppshotContext` object with app icon and transition snapshot
- `json`: machine-readable metadata
- `image_path`: path to the screenshot image on disk
- `directory`: path to the capture directory

## Related

- [`take_appshot`](/appshots:capture) — capture a fresh screenshot right now
- [`search_appshots`](/appshots:search) — find a specific past capture by name or content
