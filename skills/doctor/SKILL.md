---
name: doctor
description: Check Appshots permissions and storage health
---

# Doctor AppShots

Use when you need to diagnose issues with Appshots or verify permissions and storage are healthy.

## When to use

- Appshots isn't working or returning unexpected results
- Captures fail or come back text-only (likely a Screen Recording permission gap)
- You want to verify the `~/.appshots/` storage exists and the latest pointers are in sync
- Diagnosing why captures aren't being stored or found
- Verifying the Accessibility and Screen Recording grants for the capturing binary

## What it does

Invokes the `doctor_appshots` MCP tool, which runs health checks over permissions and storage:

1. Checks the **Accessibility** permission (`AXIsProcessTrusted`) — needed for the AX-tree walk and global hot key
2. Checks the **Screen Recording** permission (`CGPreflightScreenCaptureAccess`) — needed for the screenshot
3. Verifies the `~/.appshots/` storage root exists and its `index.json` is present
4. Verifies the latest capture and its prompt/screenshot files are present

## Output

Returns a JSON array of health checks. Each check has:
- `id`: the check name — one of `accessibility_permission`, `screen_recording_permission`, `storage_root`, `index`, `latest_capture`, `latest_prompt`, `latest_screenshot`
- `ok`: boolean — whether the check passed
- `detail`: a human-readable explanation

Any `ok: false` indicates what to fix — e.g. a failing permission check means the user must grant Accessibility or Screen Recording to the capturing binary in System Settings → Privacy & Security. The same checks are available headlessly via `appshotsctl doctor`.

## Related

- [`get_latest_appshot`](/appshots:latest) — fetch the latest capture (fails gracefully if storage issues exist)
- [`list_appshots`](/appshots:list) — list recent captures to verify indexing
