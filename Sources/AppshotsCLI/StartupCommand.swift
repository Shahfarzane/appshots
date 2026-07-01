import AppshotsCore
import Foundation

/// `appshotsctl startup …` — manage launch-at-login. The headless path installs
/// the `appshotsctl daemon` LaunchAgent and records `startupMode`; the GUI path
/// only records the mode, since registering the app's `SMAppService` login item
/// is app-only (the CLI's `Bundle.main` is the bare tool, not the `.app`).
///
/// Every mode change is persisted via ``AppshotSettingsStore/mutate(_:)``, which
/// posts the Darwin change notification so a running GUI reconciles itself.
enum StartupCommand {
    static func run(arguments: [String], store: AppshotSettingsStore) throws {
        let subcommand = arguments.first ?? "status"
        let rest = Array(arguments.dropFirst())

        switch subcommand {
        case "status":
            status(store: store, json: CLIOptions.wantsJSON(rest))
        case "enable":
            try enable(arguments: rest, store: store)
        case "disable":
            try disable(arguments: rest, store: store)
        default:
            throw CLIError(
                message: "Unknown startup subcommand: \(subcommand)\nUsage: appshotsctl startup status|enable|disable",
                exitCode: 2
            )
        }
    }

    // MARK: - Subcommands

    private static func status(store: AppshotSettingsStore, json: Bool) {
        let mode = store.load().startupMode
        let installed = LaunchAgentController().isInstalled()
        if json {
            let payload = StartupStatus(startupMode: mode.rawValue, launchAgentInstalled: installed)
            if let line = try? AppshotJSON.string(payload) { print(line) }
            return
        }
        print("startup mode: \(mode.rawValue)")
        print("daemon LaunchAgent installed: \(installed ? "yes" : "no")")
        print("note: the GUI login item is managed by the Appshots app, not the CLI.")
    }

    private static func enable(arguments: [String], store: AppshotSettingsStore) throws {
        let useGUI = arguments.contains("--gui")
        let useHeadless = arguments.contains("--headless")
        if useGUI, useHeadless {
            throw CLIError(message: "Choose either --headless or --gui, not both.", exitCode: 2)
        }
        let dryRun = CLIOptions.isDryRun(arguments)

        if useGUI {
            if dryRun {
                print("[dry-run] would set startup mode to gui (no LaunchAgent; SMAppService is app-only)")
                print("          and remove any headless daemon LaunchAgent.")
                return
            }
            try store.mutate { $0.startupMode = .gui }
            // Switching to GUI mode: remove a previously installed headless agent
            // so it no longer launches the daemon at login (a running daemon also
            // yields once it observes the mode change). Best-effort.
            try? LaunchAgentController().uninstall()
            print("startup mode set to gui.")
            print("note: the CLI cannot register the app's login item (SMAppService is app-only).")
            print("      A running Appshots app applies this; otherwise it takes effect on the next GUI launch.")
            return
        }

        // Default: headless daemon LaunchAgent.
        if dryRun {
            print("[dry-run] would set startup mode to headless and install the daemon LaunchAgent")
            print("          at ~/Library/LaunchAgents/\(LaunchAgentController.label).plist, then bootstrap it.")
            return
        }
        try store.mutate { $0.startupMode = .headless }
        do {
            try LaunchAgentController().install()
        } catch let error as LaunchAgentError {
            throw CLIError(message: error.description, exitCode: 1)
        }
        print("startup mode set to headless; daemon LaunchAgent installed.")
        print("note: the daemon binary needs its own Accessibility + Screen Recording grants")
        print("      in System Settings > Privacy & Security before the hot key will fire.")
    }

    private static func disable(arguments: [String], store: AppshotSettingsStore) throws {
        if CLIOptions.isDryRun(arguments) {
            print("[dry-run] would set startup mode to none and remove the daemon LaunchAgent.")
            return
        }
        try store.mutate { $0.startupMode = .none }
        do {
            try LaunchAgentController().uninstall()
        } catch let error as LaunchAgentError {
            throw CLIError(message: error.description, exitCode: 1)
        }
        print("startup disabled; daemon LaunchAgent removed.")
    }
}

private struct StartupStatus: Encodable {
    var startupMode: String
    var launchAgentInstalled: Bool
}
