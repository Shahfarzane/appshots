# Headless CLI usage

The Appshots capture/control surface is available from `appshotsctl`, so you can
run captures, MCP, startup control, and the global hot-key daemon from a coding
agent without launching the GUI. GUI-only surfaces such as the popover,
preview/history UI, and interactive Sparkle update flow stay in `Appshots.app`.
This doc covers capture, the daemon, and the per-binary permission story that
headless setups have to get right.

## Getting the binary

Pick whichever fits your setup:

- **Standalone release artifact (recommended for GUI-less once published):**
  `appshotsctl-<version>-arm64.zip`, signed, notarized, with its own stable TCC
  identity (`ceo.nerd.appshots.cli`). The Homebrew formula in `DevKit/Homebrew/`
  is installable only after its URL and sha256 point at a published zip.
- **App-bundled helper:** `/Applications/Appshots.app/Contents/Helpers/appshotsctl`.
- **Local build:** `swift build` → `.build/debug/appshotsctl`.

`appshotsctl help` prints the full command surface. Exit codes are `0` (ok),
`1` (failure), `2` (usage error / not found).

## Capture

```sh
appshotsctl capture                         # frontmost app → print appshot.md
appshotsctl capture --copy                  # also copy prompt + screenshot to clipboard
appshotsctl capture --app Safari            # target a running app by name…
appshotsctl capture --app com.apple.Safari  # …or by bundle identifier
appshotsctl capture --app Safari --copy
```

- `--app BUNDLE_OR_NAME` resolves a running application; without it, the
  frontmost app is captured.
- `--copy` writes the appshot markdown + screenshot to the general pasteboard.
  It works without a GUI — the CLI initializes the Cocoa pasteboard machinery on
  demand. `--copy` is also implied whenever `copyOnCapture` is enabled in
  settings (`appshotsctl config set copyOnCapture true`).

Captures land under `~/.appshots/snapshots/<date>/<capture-id>/` and update the
stable pointers (`latest.md`, `latest.txt`, `latest.json`, `index.json`). Read
them back with `appshotsctl latest` (add `--json`, `--image`, `--model-prompt`,
`--payload`, `--context`, `--events`, `--dir`, or `--metadata`),
`appshotsctl list`, or `appshotsctl search <query>`.

Streaming / timing variants for integrations: `capture --events`,
`capture --event-stream` (newline-delimited JSON, `--timeout-seconds N`, default
`120`), `capture --events --timings`, `capture --timings`, and `benchmark`.
`--app` targets are supported for normal captures and benchmarks, but rejected
for `--events` / `--event-stream`.

## Configuration

Settings live in `~/.appshots/config.json` (shared with the GUI). Every write
posts a Darwin notification, so a running app or daemon live-reloads without a
restart.

```sh
appshotsctl config list                  # all keys + values (--json for JSON)
appshotsctl config set captureSound false
appshotsctl trigger set --preset option  # option | command | shift, or --keys 58,61
appshotsctl sound disable
appshotsctl onboarding status            # report Accessibility / Screen Recording / onboarding
appshotsctl doctor                       # storage + permission health (JSON; non-zero exit on failure)
```

## The daemon (global hot key without the GUI)

The capture engine is already headless, but the **global hot key** is not: macOS
`NSEvent` global monitors require a running AppKit run loop. The `daemon`
subcommand brings one up with no menu-bar UI:

```sh
appshotsctl daemon
```

It activates as `NSApplication.accessory` (dock-less), arms the trigger-key
monitor, prewarms the capture pipeline, and blocks. Behavior to know:

- **No double-fire.** Hot-key ownership is keyed on the startup mode: the daemon
  owns the hot key only in `headless` mode, where the menu-bar app never arms its
  own monitor. If launched in any other mode — or if another daemon already holds
  the advisory `flock` at `~/.appshots/hotkey.lock` — it exits cleanly (`0`).
  GUI presence alone does not make a headless-mode daemon yield.
- **Live reload.** A `trigger`/`copyOnCapture` change from the CLI or GUI re-arms
  the running daemon's monitor immediately. If the startup mode changes away from
  `headless` (e.g. `startup enable --gui`), the daemon yields and exits.
- **Logs.** When run via the LaunchAgent, stdout/stderr go to
  `~/.appshots/daemon.out.log` / `daemon.err.log`. Otherwise tail unified
  logging: `log stream --predicate 'subsystem == "ceo.nerd.appshots"' --level debug`.

You rarely run `daemon` by hand — `appshotsctl startup enable` installs it as a
launchd LaunchAgent so it starts at login. See
[launch-at-login.md](launch-at-login.md).

## Permissions (per-binary TCC)

This is the part that trips up headless setups. macOS privacy permissions are
keyed to the **binary**, not to "Appshots" as a brand. The menu-bar app, the
standalone CLI, and the LaunchAgent daemon are **separate TCC subjects**:

- The standalone CLI carries a stable identity (`CFBundleIdentifier =
  ceo.nerd.appshots.cli`, embedded in the Mach-O via an `Info.plist` section), so
  once you grant it Accessibility + Screen Recording, the grant **persists across
  upgrades** instead of resetting on every rebuild.
- Granting the GUI app does **not** grant the CLI, and vice versa. Each binary
  that captures needs its own entries under **System Settings > Privacy &
  Security > Accessibility** and **Screen Recording**.

To grant the CLI, run a capture once so macOS surfaces the prompts:

```sh
appshotsctl capture
```

Then enable `appshotsctl` (and the daemon, if you use one) in both
**Accessibility** and **Screen Recording**, and re-run. `appshotsctl onboarding
status` and `appshotsctl doctor` report the current grant state.

### Responsible-process caveat

When you launch `appshotsctl` from a terminal, an SSH session, or a coding agent,
macOS may attribute the permission request to the **responsible parent process**
(Terminal, iTerm, the agent's host app) rather than to `appshotsctl` itself. In
that case the grant you need to toggle in System Settings is the *parent*'s, and
captures will fail with empty/blocked screenshots until the right subject is
authorized. If a capture comes back without a screenshot or accessibility tree:

1. Check which process actually holds the grant (look for the terminal/agent, not
   just `appshotsctl`, in the Privacy panes).
2. The headless **LaunchAgent daemon** sidesteps this — launchd is its
   responsible process, so the grant attaches to the daemon's own identity. For
   long-lived headless capture, prefer `startup enable --headless` over invoking
   the CLI directly from an agent.
