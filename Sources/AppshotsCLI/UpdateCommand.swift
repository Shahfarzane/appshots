import AppshotsCore
import Foundation

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
        let action = arguments.dropFirst().first ?? "status"

        switch action {
        case "on":
            try store.mutate { $0.autoUpdate = true }
            printStatus(store: store)
        case "off":
            try store.mutate { $0.autoUpdate = false }
            printStatus(store: store)
        case "status":
            printStatus(store: store)
        default:
            throw CLIError(
                message: "Unknown update action: \(action)\nUsage: appshotsctl update auto on|off|status",
                exitCode: 2
            )
        }
    }

    private static func printStatus(store: AppshotSettingsStore) {
        print("auto-update: \(store.load().autoUpdate ? "on" : "off")")
    }
}
