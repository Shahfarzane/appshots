import AppshotsCore
import CoreGraphics
import Foundation

/// `appshotsctl trigger …` — read and set the global capture trigger key codes
/// stored in `config.json`. Persisting posts the Darwin change notification so a
/// running daemon / GUI re-arms its hot-key monitor without a restart.
enum TriggerCommand {
    static func run(arguments: [String], store: AppshotSettingsStore) throws {
        let subcommand = arguments.first ?? "get"
        let rest = Array(arguments.dropFirst())

        switch subcommand {
        case "get":
            try get(store: store)
        case "set":
            try set(arguments: rest, store: store)
        case "reset":
            try store.mutate { $0.triggerKey = AppshotSettings.defaults.triggerKey }
            try get(store: store)
        default:
            throw CLIError(
                message: "Unknown trigger subcommand: \(subcommand)\nUsage: appshotsctl trigger get|set|reset",
                exitCode: 2
            )
        }
    }

    // MARK: - Subcommands

    private static func get(store: AppshotSettingsStore) throws {
        let codes = store.load().triggerKey
        let csv = codes.map(String.init).joined(separator: ",")
        let readable = codes.map(label(for:)).joined(separator: " + ")
        print("codes: \(csv)")
        print("keys: \(readable.isEmpty ? "(none)" : readable)")
    }

    private static func set(arguments: [String], store: AppshotSettingsStore) throws {
        if let preset = CLIOptions.string(arguments, name: "--preset") {
            guard let hotKey = AppshotsHotKey(rawValue: preset), hotKey != .none else {
                throw CLIError(
                    message: "Invalid preset '\(preset)': expected one of option, command, shift.",
                    exitCode: 2
                )
            }
            let codes = Array(hotKey.triggerKeyCodes).sorted()
            try store.mutate { $0.triggerKey = codes }
            try get(store: store)
            return
        }

        if let raw = CLIOptions.string(arguments, name: "--keys") {
            // Reuse the registry's validating parser so CSV rules stay identical.
            guard let entry = AppshotSettings.registryKey("triggerKey") else {
                throw CLIError(message: "Trigger key setting is unavailable.", exitCode: 1)
            }
            do {
                try store.mutate { try entry.set(&$0, raw) }
            } catch let error as AppshotSettingsError {
                throw CLIError(message: error.description, exitCode: 2)
            }
            try get(store: store)
            return
        }

        throw CLIError(
            message: "Usage: appshotsctl trigger set --preset option|command|shift | --keys 58,61",
            exitCode: 2
        )
    }

    // MARK: - Rendering

    /// Human-readable label for a raw key code. Modifier codes (which have no
    /// printable character) are named explicitly; everything else falls back to
    /// the keyboard-layout translation in `CGKeyCode.humanReadable`.
    private static func label(for code: UInt16) -> String {
        if let name = modifierNames[code] {
            return name
        }
        return CGKeyCode(code).humanReadable ?? "Key \(code)"
    }

    private static let modifierNames: [UInt16: String] = [
        0x37: "Left Command", 0x36: "Right Command",
        0x38: "Left Shift", 0x3C: "Right Shift",
        0x3A: "Left Option", 0x3D: "Right Option",
        0x3B: "Left Control", 0x3E: "Right Control",
        0x3F: "Function",
    ]
}
