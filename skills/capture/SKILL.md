---
name: capture
description: Capture the frontmost macOS application window as an appshot (screenshot + accessibility tree)
---

# Capture AppShot

Use when you need a fresh screenshot and accessibility tree of the frontmost macOS application for visual and structural context.

## When to use

- User switches focus to a different window and wants you to see the updated state
- You need the current visual state of an app (not the cached last capture)
- User asks to "take a screenshot", "capture this", or "screenshot the current window"
- You're debugging or analyzing a macOS app's visual or accessibility interface

## What it does

Invokes the `take_appshot` MCP tool, which captures the frontmost macOS app window:

1. Takes a full-resolution screenshot
2. Walks the app's accessibility tree to extract UI structure and text content
3. Generates a Codex-style `<appshot>` prompt block with structured UI state
4. Saves the capture under `~/.appshots/snapshots/<date>/<capture-id>/`
5. Updates stable pointers (`~/.appshots/latest.md`, `latest.txt`, `latest.json`)
6. Returns the prompt text and screenshot image

## Output formats

Pass `format` to customize the response:

- `codex` (default): `<appshot>` block + screenshot for model input
- `prompt`: the full appshot markdown text
- `model_prompt`: model-ready prompt format
- `context`: structured `AppshotContext` object with metadata
- `json`: machine-readable capture metadata
- `payload`: JSON with the model prompt, image path, image data URL, and metadata
- `events`: the capture status event log
- `image_path`: path to the screenshot image on disk
- `directory`: the capture directory path on disk

## Related

- [`get_latest_appshot`](/appshots:latest) — fetch the most recent capture without taking a new one
- [`search_appshots`](/appshots:search) — find a specific past capture by app, title, or content
