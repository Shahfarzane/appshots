import AppshotsCore
import Foundation

/// `appshotsctl sound enable|disable|status` — toggle the capture "shutter"
/// sound (`captureSound` in `config.json`).
enum SoundCommand {
    static func run(arguments: [String], store: AppshotSettingsStore) throws {
        let subcommand = arguments.first ?? "status"

        switch subcommand {
        case "enable":
            try store.mutate { $0.captureSound = true }
            printStatus(store: store)
        case "disable":
            try store.mutate { $0.captureSound = false }
            printStatus(store: store)
        case "status":
            printStatus(store: store)
        default:
            throw CLIError(
                message: "Unknown sound subcommand: \(subcommand)\nUsage: appshotsctl sound enable|disable|status",
                exitCode: 2
            )
        }
    }

    private static func printStatus(store: AppshotSettingsStore) {
        print("capture sound: \(store.load().captureSound ? "enabled" : "disabled")")
    }
}
