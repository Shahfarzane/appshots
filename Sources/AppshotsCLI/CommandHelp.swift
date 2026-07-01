import Foundation

/// Focused, per-subcommand help shown by `appshotsctl <command> --help` and
/// `appshotsctl help <command>`. The top-level `helpText` in `main.swift` lists
/// every command; these blocks zoom in on one command's options and semantics.
enum CommandHelp {
    /// Returns the help block for `command`, or a short pointer for unknown ones.
    static func text(for command: String) -> String {
        switch command {
        case "capture":
            return """
            appshotsctl capture [output] [--app BUNDLE_OR_NAME] [--copy]

            Capture the frontmost macOS app (or a specific app with --app) and persist
            it under ~/.appshots/. Default output is the <appshot> prompt (appshot.md).

              --app BUNDLE_OR_NAME   Capture a specific running app, not the frontmost
              --copy                 Also copy the prompt + screenshot to the clipboard

            Output modes (pick one): --image --json --model-prompt --payload --context
              --events --event-stream [--timeout-seconds N] --timings --dir --metadata
            """
        case "latest":
            return """
            appshotsctl latest [output]

            Print the most recent capture without taking a new one. Accepts the same
            output modes as `capture` (default: the <appshot> prompt). --event-stream is
            not supported here.
            """
        case "list":
            return """
            appshotsctl list [--limit N]

            Print recent captures as a JSON array (default limit 20).
            """
        case "search":
            return """
            appshotsctl search <query> [--limit N]

            Search indexed captures by app, window title, URL, or captured text. Prints
            a JSON array (default limit 20).
            """
        case "delete":
            return """
            appshotsctl delete <capture-id>

            Delete a capture by id.
            """
        case "benchmark":
            return """
            appshotsctl benchmark [--app BUNDLE_OR_NAME] [--count N] [--warmup N]

            Capture repeatedly and print per-phase p50/p95 timings as JSON.
              --app BUNDLE_OR_NAME   Target a specific running app
              --count N              Measured captures (default 10)
              --warmup N             Warmup captures before measuring (default 2)
            """
        case "doctor":
            return """
            appshotsctl doctor

            Print Accessibility + Screen Recording + storage health checks as JSON;
            exits non-zero if any check fails.
            """
        case "mcp":
            return """
            appshotsctl mcp                                      Run the stdio MCP server
            appshotsctl mcp install [--scope S] [--project DIR]  Register for Claude Code
            appshotsctl mcp uninstall [--scope S]                Remove the registration
            appshotsctl mcp status [--json]                      Show registration state

            With no subcommand, runs the native JSON-RPC stdio server. install/uninstall
            register this CLI as the `appshots` MCP server. --scope is user|project.
              -n, --dry-run   Print the claude command without running it
            """
        case "daemon":
            return """
            appshotsctl daemon

            Run the headless hot-key host (no GUI). It owns the trigger chord only in
            `headless` startup mode. You normally install it with `startup enable
            --headless` rather than running it by hand.
            """
        case "config":
            return """
            appshotsctl config list [--json]
            appshotsctl config get <key>
            appshotsctl config set <key> <value>
            appshotsctl config unset <key>
            appshotsctl config path

            Read/write the shared settings in ~/.appshots/config.json (a running GUI
            live-reloads). Keys: triggerKey, captureSound, copyOnCapture,
            onboardingCompleted, startupMode (none|gui|headless), autoUpdate,
            showInDock, mcpDefaultScope (user|project), mcpLastProjectDirectory.
            """
        case "trigger":
            return """
            appshotsctl trigger get
            appshotsctl trigger set --preset option|command|shift
            appshotsctl trigger set --keys 58,61
            appshotsctl trigger reset

            Show or set the capture trigger key. --preset uses a named modifier pair;
            --keys takes raw CGKeyCodes (CSV). reset restores the default (58,61).
            """
        case "sound":
            return """
            appshotsctl sound enable|disable|status

            Toggle or show the capture (shutter) sound.
            """
        case "update":
            return """
            appshotsctl update auto on|off|status

            Toggle or show Sparkle auto-update for the GUI app.
            """
        case "startup":
            return """
            appshotsctl startup status [--json]
            appshotsctl startup enable [--headless|--gui] [--dry-run]
            appshotsctl startup disable [--dry-run]

            Manage launch-at-login. --headless (default) installs the daemon LaunchAgent;
            --gui records GUI-login-item mode (the app registers its SMAppService login
            item). The two modes are mutually exclusive. -n/--dry-run previews only.
            """
        case "onboarding":
            return """
            appshotsctl onboarding status

            Report Accessibility + Screen Recording permission state and whether
            onboarding has completed.
            """
        case "completion":
            return """
            appshotsctl completion zsh|bash

            Print a shell completion script. Install:
              zsh:  appshotsctl completion zsh > "${fpath[1]}/_appshotsctl"
              bash: appshotsctl completion bash > /usr/local/etc/bash_completion.d/appshotsctl
            """
        case "version":
            return "appshotsctl version   Print the appshotsctl version."
        default:
            return "No detailed help for '\(command)'. Run `appshotsctl help` for the command list."
        }
    }
}
