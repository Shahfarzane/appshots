import AppshotsCore
import Foundation

/// `appshotsctl config …` — read and write the shared `config.json` via the
/// string-keyed ``AppshotSettings`` registry. Writes go through
/// ``AppshotSettingsStore/mutate(_:)``, which posts the Darwin change
/// notification so a running GUI / daemon live-reloads.
enum ConfigCommand {
    static func run(arguments: [String], store: AppshotSettingsStore) throws {
        let subcommand = arguments.first ?? "list"
        let rest = Array(arguments.dropFirst())

        switch subcommand {
        case "list":
            try list(arguments: rest, store: store)
        case "get":
            try get(arguments: rest, store: store)
        case "set":
            try set(arguments: rest, store: store)
        case "unset":
            try unset(arguments: rest, store: store)
        case "path":
            print(store.configURL.path)
        default:
            throw CLIError(
                message: "Unknown config subcommand: \(subcommand)\nUsage: appshotsctl config list|get|set|unset|path",
                exitCode: 2
            )
        }
    }

    // MARK: - Subcommands

    private static func list(arguments: [String], store: AppshotSettingsStore) throws {
        let settings = store.load()
        if arguments.contains("--json") {
            let entries = AppshotSettings.registry.map {
                ConfigEntry(key: $0.key, value: $0.get(settings))
            }
            print(try AppshotJSON.string(entries))
        } else {
            for entry in AppshotSettings.registry {
                print("\(entry.key) = \(entry.get(settings))")
            }
        }
    }

    private static func get(arguments: [String], store: AppshotSettingsStore) throws {
        guard let key = arguments.first else {
            throw CLIError(message: "Usage: appshotsctl config get <key>", exitCode: 2)
        }
        guard let entry = AppshotSettings.registryKey(key) else {
            throw CLIError(message: AppshotSettingsError.unknownKey(key).description, exitCode: 2)
        }
        print(entry.get(store.load()))
    }

    private static func set(arguments: [String], store: AppshotSettingsStore) throws {
        guard arguments.count >= 2 else {
            throw CLIError(message: "Usage: appshotsctl config set <key> <value>", exitCode: 2)
        }
        let key = arguments[0]
        let value = arguments[1]
        guard let entry = AppshotSettings.registryKey(key) else {
            throw CLIError(message: AppshotSettingsError.unknownKey(key).description, exitCode: 2)
        }
        do {
            try store.mutate { try entry.set(&$0, value) }
        } catch let error as AppshotSettingsError {
            throw CLIError(message: error.description, exitCode: 2)
        }
        print("\(key) = \(entry.get(store.load()))")
    }

    private static func unset(arguments: [String], store: AppshotSettingsStore) throws {
        guard let key = arguments.first else {
            throw CLIError(message: "Usage: appshotsctl config unset <key>", exitCode: 2)
        }
        guard let entry = AppshotSettings.registryKey(key) else {
            throw CLIError(message: AppshotSettingsError.unknownKey(key).description, exitCode: 2)
        }
        // Reset this single key by re-applying its factory-default rendering.
        let defaultValue = entry.get(.defaults)
        do {
            try store.mutate { try entry.set(&$0, defaultValue) }
        } catch let error as AppshotSettingsError {
            throw CLIError(message: error.description, exitCode: 2)
        }
        print("\(key) = \(entry.get(store.load()))")
    }
}

/// A single `{key, value}` row emitted by `config list --json`, encoded in the
/// registry's canonical order.
private struct ConfigEntry: Encodable {
    let key: String
    let value: String
}
