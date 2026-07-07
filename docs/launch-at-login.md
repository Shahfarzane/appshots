# Launch at login

Appshots can start itself at login two different ways. They are **mutually
exclusive** — pick the one that matches how you run Appshots.

| | GUI login item | Headless LaunchAgent |
|---|---|---|
| Mechanism | `SMAppService.mainApp` | launchd user agent + `appshotsctl daemon` |
| Starts | the full menu-bar app | the dock-less daemon (hot key only, no UI) |
| Set from | app **General** settings, or `startup enable --gui` | `startup enable` / `startup enable --headless` |
| `startupMode` | `gui` | `headless` |
| Needs | System Settings > Login Items approval | per-binary Accessibility + Screen Recording grant |

`startupMode` in `~/.appshots/config.json` records which path is active; `none`
means launch-at-login is off.

## GUI login item

In the menu-bar app, open **Settings > General > Startup** and toggle **Launch at
Login**. This registers the app with `SMAppService.mainApp`
(`Sources/Appshots/Startup/LoginItemController.swift`).

macOS may put the item in a **requires-approval** state: the General pane then
shows an "Open Login Items" button. Approve **Appshots** under **System Settings
> General > Login Items** to finish enabling. The controller reads the live
`SMAppService` status every time (the user can change it out of band in System
Settings), so the toggle always reflects reality.

The CLI cannot register the app's login item — `SMAppService.mainApp` is
app-only, and the CLI's `Bundle.main` is the bare tool, not the `.app`. So:

```sh
appshotsctl startup enable --gui
```

only **records** the GUI intent (`startupMode = gui`). A running Appshots app
applies it; otherwise it takes effect on the next GUI launch.

## Headless LaunchAgent

For GUI-less setups, install the daemon as a launchd user agent:

```sh
appshotsctl startup enable                # default: headless
appshotsctl startup enable --headless     # explicit
appshotsctl startup status                # mode + whether the LaunchAgent is installed
```

This writes `~/Library/LaunchAgents/ceo.nerd.appshots.cli.daemon.plist`
(`RunAtLoad` + `KeepAlive`, running `appshotsctl daemon`), bootstraps it into the
GUI domain via `launchctl` so it starts immediately, and sets
`startupMode = headless`. If the LaunchAgent install fails, the previous
`startupMode` is restored so the hot key is never left owned by nobody.
stdout/stderr go to `~/.appshots/daemon.out.log` and
`daemon.err.log`. Implemented in
`Sources/AppshotsCore/Startup/LaunchAgentController.swift`.

> The daemon binary needs its **own** Accessibility + Screen Recording grant in
> System Settings > Privacy & Security before the hot key will fire — it is a
> separate TCC subject from the GUI app. See
> [headless-cli.md](headless-cli.md#permissions-per-binary-tcc).

Passing both `--headless` and `--gui` is an error (exit `2`).

## Mutual exclusion

The two paths shouldn't run together — that would arm two observe-only hot-key
monitors and fire the chord twice. The daemon guards against this at runtime: it
exits cleanly outside `startupMode = headless` or if another daemon already holds
`~/.appshots/hotkey.lock`. GUI presence alone does not make a headless-mode
daemon yield; in headless mode the GUI does not arm its own monitor. Conceptually,
choose **one** of:

- GUI login item (app starts, hosts the hot key), or
- headless LaunchAgent (daemon starts, hosts the hot key).

## Cleanup / uninstall

```sh
appshotsctl startup disable
```

This boots the agent out of launchd, removes the `.plist`, and sets
`startupMode = none`. For the GUI login item, turn off **Launch at Login** in the
app's General settings (or remove **Appshots** under System Settings > Login
Items).

Removing the apps/binaries themselves: drag `Appshots.app` to the Trash and/or
remove the standalone `appshotsctl` binary. Run `appshotsctl startup disable`
**before** removing the CLI so the LaunchAgent plist doesn't point at a missing
binary. The `~/.appshots/` directory (captures + `config.json`) is left in
place; delete it manually if you want a clean slate.
