# Appshots MCP Setup

Appshots ships a **native** MCP server built into the `appshotsctl` helper — no
Python required. The helper is embedded in the app bundle at
`Appshots.app/Contents/Helpers/appshotsctl`, available as a standalone release
artifact once published, or built locally with `swift build`, so the server keeps
working after the source repo is gone.

## Recommended: the Claude Code plugin

The plugin registers the MCP server for you — no manual `claude mcp add`.

```text
/plugin marketplace add Shahfarzane/appshots
/plugin install appshots
```

The plugin (`.claude-plugin/plugin.json`) declares the MCP server as:

```json
"mcpServers": {
  "appshots": {
    "command": "${CLAUDE_PLUGIN_ROOT}/bin/appshotsctl",
    "args": ["mcp"]
  }
}
```

`bin/appshotsctl` is a resolver script that locates your installed `appshotsctl`
(Homebrew, the `Appshots.app` bundle, `PATH`, or a repo `.build/`) and execs it,
so the server works whether or not the app is installed. The plugin also bundles
skills (`capture`, `latest`, `list`, `search`, `doctor`).

## CLI command: `appshotsctl mcp install`

`appshotsctl` can register *itself* as the Claude MCP server (handy for the
standalone CLI, which has no enclosing `.app`):

```sh
appshotsctl mcp install --scope user                 # global, every project
appshotsctl mcp install --scope project --project .  # writes .mcp.json in DIR
appshotsctl mcp status                               # claude CLI + helper + registration
appshotsctl mcp uninstall --scope user
```

The chosen scope / project directory are remembered in `config.json`
(`mcpDefaultScope`, `mcpLastProjectDirectory`), so later invocations and the GUI
share the same defaults. `install` is idempotent — it clears a prior
registration in the same scope first.

## Enable from the app

Open Appshots Settings (right-click the menu-bar icon → **Settings…**) → the
**MCP** tab, pick **User** (global) or **Project** scope, and Appshots
registers the server with Claude Code for you and shows live status.

## Manual (Claude Code CLI)

```sh
# User scope (available in every project)
claude mcp add appshots -s user -- "/Applications/Appshots.app/Contents/Helpers/appshotsctl" mcp

# Project scope (writes .mcp.json in the current directory)
claude mcp add appshots -s project -- "/Applications/Appshots.app/Contents/Helpers/appshotsctl" mcp

# Verify / remove
claude mcp list
claude mcp remove appshots -s user
```

If you installed the standalone CLI, point at it instead:

```sh
claude mcp add appshots -s user -- "$(command -v appshotsctl)" mcp
```

During development you can point at the built helper:

```sh
swift build
claude mcp add appshots -s user -- "$(pwd)/.build/debug/appshotsctl" mcp
```

## Shell-only agents

If the agent can run shell commands, no MCP setup is required:

```sh
appshotsctl capture
appshotsctl capture --copy
appshotsctl latest
appshotsctl latest --image
```

See [docs/headless-cli.md](docs/headless-cli.md) for the full headless workflow,
including per-binary Accessibility / Screen Recording grants.

## Available Tools

- `take_appshot`
- `get_latest_appshot`
- `get_appshot_image`
- `list_appshots`
- `search_appshots`
- `delete_appshot`
- `doctor_appshots`

## Available Prompts

Prompts are user-invocable: MCP clients surface them as slash commands (Claude
Code) or attach-menu entries (Claude Desktop), and the appshot lands directly
in your message as text + image, with no tool round-trip.

- `latest-appshot` — attach the most recent capture (press the hot key first)
- `appshot` — capture now and attach; the optional `app` argument targets a
  specific running app by name or bundle id (recommended: from a chat client
  the frontmost app is usually the chat window itself)
