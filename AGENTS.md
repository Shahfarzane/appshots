# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Cursor, etc.) working in this repo.

## What this is

Appshots is a macOS menu-bar app that sends app context to coding agents. On a hot key
(left Option + right Option) or popover click it captures the frontmost window: a screenshot
plus the app's accessibility tree, rendered into a Codex-style `<appshot>` prompt, and copies
the prompt + screenshot to the clipboard. Every capture is persisted under `~/.appshots/` so
CLI and MCP agents can read it back. Inspired by OpenAI Codex appshots; the goal is to give
Claude Code and other agents the same visual + accessibility context on macOS.

The accessibility/screenshot capture is done by a built-in macOS accessibility & screenshot capture engine
(`AppshotsCore/Capture/Engine`) — no external automation server.

## Targets (Package.swift / project.yml)

Three products, one shared library:

- **`AppshotsCore`** (`Sources/AppshotsCore`) — the library. Capture pipeline, on-disk store,
  prompt codec, structured-state rendering, the whole `Capture/Engine` accessibility/
  screenshot engine, plus the shared **settings store** (`Settings/`), **hot-key stack**
  (`HotKey/`), **Claude MCP registrar** (`MCP/`), and headless **LaunchAgent** controller
  (`Startup/`). Has no UI and no run loop; both other targets depend on it. Put logic here.
- **`Appshots`** (`Sources/Appshots`) — the menu-bar app (SwiftUI + AppKit, `LSUIElement`).
  Status item, popover, hot key, onboarding/permissions, history & preview windows, MCP
  settings UI, Sparkle auto-update, and the GUI `SMAppService` login item
  (`Startup/LoginItemController.swift`). Bundles `appshotsctl` as a helper.
- **`appshotsctl`** (`Sources/AppshotsCLI`) — the CLI, the native MCP stdio server
  (`mcp` subcommand), **and** a headless hot-key host (`daemon` subcommand). No Python.
  Embedded in the app bundle at `Appshots.app/Contents/Helpers/appshotsctl`, shipped
  standalone via `brew install appshotsctl`, and used by the Claude Code plugin — so it keeps
  working without the source repo. The command surface reaches GUI/CLI parity:
  `capture` (with `--copy` / `--app`), `config`/`trigger`/`sound`/`update`/`startup`/
  `onboarding`/`mcp install|uninstall|status`, plus `daemon`. The CLI target embeds an
  `Info.plist` section (`Resources/CLI/Info.plist`, `CREATE_INFOPLIST_SECTION_IN_BINARY=YES`)
  so the bare binary has a stable TCC identity (`ceo.nerd.appshots.cli`).

## Build, test, run

This is a SwiftPM package; `Appshots.xcodeproj` is **generated** from `project.yml` via
xcodegen — never hand-edit the `.xcodeproj` (it's gitignored). Regenerate with `xcodegen`.

```sh
swift build                       # build everything (debug)
swift test                        # run AppshotsCoreTests (Swift Testing framework)
swift build -c release            # release build
.build/debug/appshotsctl latest   # run the CLI after building

scripts/build-app.sh [debug|release]   # assemble a runnable Appshots.app under .build/
xcodegen                               # regenerate Appshots.xcodeproj from project.yml
```

Toolchain: Swift 6 (language mode `.v6`, strict concurrency), macOS 14+ deployment target.
CI: `.github/workflows/ci.yml` runs `swift build` + `swift test` on pull requests and pushes to
`main`; `.github/workflows/macos-release-production.yml` builds/signs/notarizes a release on `v*`
tags. Still run `swift test` locally before pushing.

## Conventions & gotchas

- **Logging: use `AppLog`, never `print`/stdout for diagnostics.** All targets log through
  `AppshotsCore/AppLog.swift` (`os.Logger`, subsystem `ceo.nerd.appshots`, per-area categories
  like `capture`, `store`, `mcp`). `print`/stdout is reserved for CLI command output and the
  MCP JSON-RPC stream — writing diagnostics there corrupts the MCP stdio loop. Tail logs with:
  `log stream --predicate 'subsystem == "ceo.nerd.appshots"' --level debug`.
- **Swift 6 strict concurrency.** New types crossing concurrency boundaries need `Sendable`
  (or a documented `@unchecked Sendable` with a lock, as in `AppshotCaptureStreamState`).
  App/UI code is `@MainActor`.
- **Storage layout** (`AppshotStore`, root `~/.appshots/`): captures live in
  `snapshots/<date>/<capture-id>/` (`screenshot.png`, `transition-snapshot.png`,
  `accessibility_tree.{txt,json}`, `page_url.txt`, `appshot.md`, `metadata.json`). Stable
  pointers `latest.md`, `latest.txt`, `latest.json`, and `index.json` are updated on every save
  — keep them in sync if you touch the save path. `transition-snapshot.png` is a separate,
  best-effort polished preview (rounded screenshot card + bottom fade + centered app icon +
  title) rendered after the screenshot is copied; it feeds the capture flight animation and
  `AppshotContext.transitionSnapshotDataURL` / `transitionSnapshotHeight`. The full-res
  `screenshot.png` is what feeds the model + clipboard and is never mutated — a transition
  render failure logs via `AppLog.store` and leaves `transitionSnapshotPath` nil without failing
  the capture.
- **MCP / output shapes.** Tool/format contract lives in `AppshotsCLI/AppshotMCPServer.swift`,
  `AppshotPromptCodec`, and `AppshotContext`. `format: "codex"` returns the Codex `<appshot>`
  text + image; `"context"` returns the structured `AppshotContext`; `"events"` returns the
  capture status log. Tests in `AppshotStoreTests` pin the exact prompt strings — update them
  together.
- **Settings live in `~/.appshots/config.json`, not `UserDefaults`.** `AppshotSettingsStore`
  (`Settings/`) is the single source of truth shared by the GUI and CLI; `AppshotSettings` is
  the schema + a string-keyed registry that backs `config get/set/list/unset`. Every `save`
  posts the Darwin notification `ceo.nerd.appshots.settings.changed`, so a CLI write
  live-reloads a running GUI / `daemon` via `AppshotSettingsStore.observe`. `AppshotSettingsMigration`
  one-way seeds the file from legacy `UserDefaults` the first time (never deletes the old keys).
  Keep the registry, the struct, and the CLI command files in sync when adding a key.
- **Per-binary TCC.** The app, the standalone CLI, and the LaunchAgent daemon are **separate**
  macOS TCC subjects — each needs its own Accessibility + Screen Recording grant. The standalone
  CLI's stable identity comes from the embedded `Info.plist` (`ceo.nerd.appshots.cli`). When the
  CLI is launched from a terminal/agent, the grant may attach to the responsible parent process;
  see `docs/headless-cli.md`.
- **Launch-at-login has two paths.** GUI = `SMAppService.mainApp` login item (app-only;
  `LoginItemController`, may require System Settings approval). Headless = `LaunchAgentController`
  (`Startup/`) writing `~/Library/LaunchAgents/ceo.nerd.appshots.cli.daemon.plist` and
  bootstrapping `appshotsctl daemon` via `launchctl`. `startupMode` records which is active; the
  two are mutually exclusive. The `daemon` itself (`AppshotsCLI/AppshotDaemon.swift`) is an
  `NSApplication.accessory` host that owns the hot key **only** in `headless` mode (where the GUI
  never arms its own monitor); it exits cleanly if launched in any other `startupMode` or while
  another daemon holds the `~/.appshots/hotkey.lock` flock, and yields when the mode changes away
  from headless — so the chord never double-fires.
- **`Capture/Engine`** is the largest, most intricate area (background AX walking, window
  resolution, ScreenCaptureKit, Chromium AX activation). Prefer small, surgical changes and
  read `docs/codex-appshots-deep-dive.md` and `docs/` plans before reworking capture.
- **`Sources/Appshots/Vendor/PermissionFlow`** is vendored third-party code — avoid
  restyling it; change only what a fix requires.

## Layout quick map

```
Sources/AppshotsCore/        library, organized by responsibility:
  Model/                     AppshotRecord, AppshotContext, capture-event model
  Store/                     on-disk store (~/.appshots), image/PNG encoding, page-URL extraction
  Settings/                  config.json store + schema/registry + legacy migration (Darwin notify)
  Prompt/                    <appshot> prompt codec + snapshot/text renderers
  Capture/                   AppshotCaptureService (entry point)
    Engine/                  AX tree + screenshot engine (the heavy lifting)
  HotKey/                    global trigger monitor + key-code helpers (shared by app + daemon)
  MCP/                       ClaudeMCPRegistrar (claude mcp add/remove, self-helper resolution)
  Startup/                   LaunchAgentController (headless daemon launchd plist + launchctl)
  Output/                    output-format enum, shared JSON encoders, doctor checks
  AppLog.swift               unified-logging facade — log through this
Sources/Appshots/            menu-bar app (SwiftUI/AppKit), MCP settings, onboarding, Sparkle
  Startup/                   LoginItemController (SMAppService GUI login item)
Sources/AppshotsCLI/         appshotsctl CLI + MCP stdio server + daemon + per-command files
Resources/CLI/Info.plist     embedded plist giving the bare CLI its TCC identity
.claude-plugin/              Claude Code plugin manifest + marketplace (registers the MCP server)
skills/                      plugin skills (capture, latest, list, search, doctor)
bin/appshotsctl              plugin resolver shim → finds the installed appshotsctl
DevKit/Homebrew/             appshotsctl.rb formula (standalone CLI: brew install appshotsctl)
Tests/AppshotsCoreTests/     Swift Testing tests (swift test)
docs/                        capture/codex deep-dive, headless-cli, launch-at-login, design plans
DevKit/Scripts/              release: sign, notarize, DMG + standalone CLI zip, appcast, R2 upload
scripts/build-app.sh         assemble a local runnable .app
project.yml                  xcodegen source of truth (.xcodeproj is generated/gitignored)
```

## Conventions for changes

- Match the surrounding Swift style (naming, comment density, file organization). Files are
  small and single-purpose — follow that when adding new ones.
- Do **not** add Claude Code / Anthropic attribution to commits, PRs, or any artifact.
- When you change capture output, the prompt codec, or the store layout, update the pinned
  tests and the user-facing docs (`README.md`, `SKILL.md`, `MCP_SETUP.md`) in the same change.
