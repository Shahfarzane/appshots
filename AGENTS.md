# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Cursor, …) working in this repo.

## What this is

Appshots is a macOS menu-bar app that gives coding agents visual + accessibility context. On a
hot key (left Option + right Option) or popover click it captures the frontmost window — a
screenshot plus the app's accessibility tree — renders it into a Codex-style `<appshot>` prompt,
and copies the prompt + screenshot to the clipboard. Every capture is persisted under
`~/.appshots/` so CLI and MCP agents can read it back. Capture is done by a built-in engine
(`AppshotsCore/Capture/Engine`) — no external automation server.

## Targets

One shared library, two executables (`Package.swift` / `project.yml`):

- **`AppshotsCore`** (`Sources/AppshotsCore`) — the library: capture pipeline + engine, on-disk
  store, prompt codec, settings store, hot-key stack, MCP registrar, headless LaunchAgent. No UI,
  no run loop; both executables depend on it. **Put logic here.**
- **`Appshots`** (`Sources/Appshots`) — the menu-bar app (SwiftUI + AppKit, `LSUIElement`): status
  item, popover, onboarding/permissions, settings, history/preview, Sparkle auto-update, and the
  GUI `SMAppService` login item. Bundles `appshotsctl` as a helper.
- **`appshotsctl`** (`Sources/AppshotsCLI`) — the CLI, the MCP stdio server (`mcp`), and a headless
  hot-key host (`daemon`). Shipped inside the app bundle *and* standalone via `brew install
  appshotsctl`, so it works without the source repo. Reaches GUI/CLI parity (`capture`, `config`,
  `trigger`, `sound`, `update`, `startup`, `onboarding`, `mcp`, `daemon`). Its embedded
  `Info.plist` (`Resources/CLI/Info.plist`) gives the bare binary a stable TCC identity
  (`ceo.nerd.appshots.cli`).

## Build, test, run

SwiftPM package; `Appshots.xcodeproj` is **generated** from `project.yml` via xcodegen — never
hand-edit it (it's gitignored). Toolchain: Swift 6 (strict concurrency), macOS 14+.

```sh
swift build                       # build everything (debug)
swift test                        # run the test suite (Swift Testing)
.build/debug/appshotsctl latest   # run the CLI
scripts/build-app.sh [release]    # assemble a runnable Appshots.app under .build/
xcodegen                          # regenerate the .xcodeproj
```

CI runs `swift build` + `swift test` on PRs/pushes to `main`; `v*` tags build/sign/notarize a
release. Run `swift test` before pushing.

## Gotchas (the ones that bite)

- **Log via `AppLog`, never `print`/stdout.** All targets log through `AppshotsCore/AppLog.swift`
  (`os.Logger`, subsystem `ceo.nerd.appshots`). `print`/stdout is reserved for CLI output and the
  MCP JSON-RPC stream — diagnostics there corrupt the MCP loop. Tail:
  `log stream --predicate 'subsystem == "ceo.nerd.appshots"'`.
- **Settings live in `~/.appshots/config.json`, not `UserDefaults`.** `AppshotSettingsStore` is the
  single source of truth shared by GUI + CLI; `AppshotSettings` is the schema + string-keyed
  registry backing `config get/set/list/unset`. Every save posts a Darwin notification so a CLI
  write live-reloads a running GUI/daemon. Adding a key → update the struct, the registry, and the
  CLI command together.
- **Wire contracts are pinned by tests.** The `<appshot>` prompt strings, the MCP tool/format output
  (`AppshotMCPServer`, `AppshotPromptCodec`, `AppshotContext`), and the `~/.appshots/` store layout
  (`snapshots/<date>/<id>/…` plus `latest.{md,txt,json}` + `index.json`, updated on every save) are
  consumed by external agents. `AppshotStoreTests` / `AppshotSettingsTests` pin them — change code
  and tests together, and keep output byte-identical otherwise.
- **Per-binary TCC.** The app, the standalone CLI, and the daemon are separate macOS TCC subjects —
  each needs its own Accessibility + Screen Recording grant. See `docs/headless-cli.md`.
- **Launch-at-login is two mutually-exclusive paths.** GUI = `SMAppService` login item
  (`LoginItemController`); headless = `LaunchAgentController` bootstrapping `appshotsctl daemon` via
  launchctl. `startupMode` records which is active; the daemon owns the hot key **only** in
  `headless` mode (guarded by the `~/.appshots/hotkey.lock` flock) so the chord never double-fires.
- **`Capture/Engine` is the intricate, perf-sensitive area** (background AX walking, ScreenCaptureKit,
  Chromium AX activation). Prefer small, surgical changes; read `docs/codex-appshots-deep-dive.md`
  first.
- **`Sources/Appshots/Vendor/PermissionFlow` is vendored** — change only what a fix requires.
- **Swift 6 strict concurrency:** types crossing actor boundaries need `Sendable` (or a documented
  `@unchecked Sendable` + lock); app/UI code is `@MainActor`.

## Layout

```
Sources/AppshotsCore/   library, by responsibility:
  Capture/ + Capture/Engine/   capture service + the AX-tree/screenshot engine (heavy lifting)
  Store/                       on-disk store (~/.appshots), image/PNG encoding
  Settings/                    config.json store + schema/registry + legacy migration
  Prompt/                      <appshot> prompt codec + renderers
  Model/ HotKey/ MCP/ Startup/ Output/   models · hot-key stack · MCP registrar · LaunchAgent · output formats
  AppLog.swift                 unified-logging facade
Sources/Appshots/       menu-bar app (SwiftUI/AppKit); Theme/Theme.swift; Vendor/PermissionFlow (vendored)
Sources/AppshotsCLI/    appshotsctl CLI + MCP stdio server + daemon
.claude-plugin/ skills/ bin/   Claude Code plugin (registers the MCP server) + resolver shim
DevKit/                 release.sh (sign/notarize/DMG/R2) + Homebrew formula
project.yml             xcodegen source of truth (.xcodeproj is generated)
```

## Conventions

- Match the surrounding Swift style. Files are generally small and single-purpose; group
  closely-related small types into one file when it reads better (e.g. `Theme.swift`,
  `AppshotOutput.swift`).
- **No** Claude Code / Anthropic attribution in commits, PRs, or any artifact.
- Changing capture output, the prompt codec, or the store layout → update the pinned tests and the
  user-facing docs (`README.md`, `SKILL.md`, `MCP_SETUP.md`) in the same change.
