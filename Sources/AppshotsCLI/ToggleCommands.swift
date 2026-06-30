import AppshotsCore
import Foundation

/// `appshotsctl sound enable|disable|status` — toggle the capture "shutter"
/// sound (`captureSound` in `config.json`).
enum SoundCommand {
    static func run(arguments: [String], store: AppshotSettingsStore) throws {
        try toggleBool(
            action: arguments.first ?? "status",
            enableKeyword: "enable",
            disableKeyword: "disable",
            keyPath: \.captureSound,
            store: store,
            status: { "capture sound: \($0 ? "enabled" : "disabled")" },
            unknownActionMessage: {
                "Unknown sound subcommand: \($0)\nUsage: appshotsctl sound enable|disable|status"
            }
        )
    }
}

/// `appshotsctl update auto on|off|status` — toggle Sparkle automatic updates
/// (`autoUpdate` in `config.json`).
enum UpdateCommand {
    static func run(arguments: [String], store: AppshotSettingsStore) throws {
        guard arguments.first == "auto" else {
            throw CLIError(
                message: "Usage: appshotsctl update auto on|off|status",
                exitCode: 2
            )
        }
        try toggleBool(
            action: arguments.dropFirst().first ?? "status",
            enableKeyword: "on",
            disableKeyword: "off",
            keyPath: \.autoUpdate,
            store: store,
            status: { "auto-update: \($0 ? "on" : "off")" },
            unknownActionMessage: {
                "Unknown update action: \($0)\nUsage: appshotsctl update auto on|off|status"
            }
        )
    }
}

/// Shared shape for the boolean toggle subcommands (`sound`, `update`): flip a
/// `Bool` in `config.json` and print its current state. Each command supplies its
/// enable/disable keywords, the settings key path, and the status / error strings,
/// so the printed and error text stay identical to the per-command originals.
private func toggleBool(
    action: String,
    enableKeyword: String,
    disableKeyword: String,
    keyPath: WritableKeyPath<AppshotSettings, Bool>,
    store: AppshotSettingsStore,
    status: (Bool) -> String,
    unknownActionMessage: (String) -> String
) throws {
    switch action {
    case enableKeyword:
        try store.mutate { $0[keyPath: keyPath] = true }
    case disableKeyword:
        try store.mutate { $0[keyPath: keyPath] = false }
    case "status":
        break
    default:
        throw CLIError(message: unknownActionMessage(action), exitCode: 2)
    }
    print(status(store.load()[keyPath: keyPath]))
}
