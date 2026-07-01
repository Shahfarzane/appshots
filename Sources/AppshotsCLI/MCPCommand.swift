import AppshotsCore
import Foundation

/// `appshotsctl mcp install|uninstall|status` — the CLI equivalent of the in-app
/// "Enable MCP for Claude Code". Unlike the GUI, which registers its bundled
/// `Contents/Helpers/appshotsctl`, this registers the *running* CLI binary as the
/// MCP helper via ``ClaudeMCPRegistrar/selfExecutableHelperURL()`` so a
/// standalone install wires itself up without an enclosing `.app`.
///
/// The chosen scope / project directory are persisted into
/// `mcpDefaultScope` / `mcpLastProjectDirectory` so later invocations and the GUI
/// share the same defaults.
enum MCPCommand {
    /// Subcommands that route here; a bare `mcp` still launches the stdio server.
    static let subcommands: Set<String> = ["install", "uninstall", "status"]

    static func run(arguments: [String], store: AppshotSettingsStore) throws {
        let subcommand = arguments.first ?? "status"
        let rest = Array(arguments.dropFirst())
        let registrar = ClaudeMCPRegistrar(helperURLOverride: ClaudeMCPRegistrar.selfExecutableHelperURL())

        switch subcommand {
        case "install":
            try install(arguments: rest, store: store, registrar: registrar)
        case "uninstall":
            try uninstall(arguments: rest, store: store, registrar: registrar)
        case "status":
            try status(arguments: rest, store: store, registrar: registrar)
        default:
            throw CLIError(
                message: "Unknown mcp subcommand: \(subcommand)\nUsage: appshotsctl mcp install|uninstall|status",
                exitCode: 2
            )
        }
    }

    // MARK: - Subcommands

    private static func install(arguments: [String], store: AppshotSettingsStore, registrar: ClaudeMCPRegistrar) throws {
        let scope = try resolveScope(arguments: arguments, store: store)
        let projectDirectory = resolveProjectDirectory(arguments: arguments, store: store)

        if CLIOptions.isDryRun(arguments) {
            let helper = registrar.environmentSynchronously().helperPath ?? "appshotsctl"
            let target = scope == .project ? " in \(projectDirectory?.path ?? "<--project DIR required>")" : ""
            print("[dry-run] would register appshots as a \(scope.rawValue)-scoped Claude MCP server\(target):")
            print("          claude mcp add appshots -s \(scope.rawValue) -- \(helper) mcp")
            return
        }

        do {
            switch scope {
            case .user:
                try registrar.enableUserSynchronously()
            case .project:
                guard let projectDirectory else {
                    throw CLIError(
                        message: "Project scope requires --project DIR (or a previously stored project directory).",
                        exitCode: 2
                    )
                }
                try registrar.enableProjectSynchronously(directory: projectDirectory)
            }
        } catch let error as MCPError {
            throw CLIError(message: error.errorDescription ?? "MCP registration failed.", exitCode: 1)
        }

        try store.mutate { settings in
            settings.mcpDefaultScope = scope.rawValue
            if scope == .project, let projectDirectory {
                settings.mcpLastProjectDirectory = projectDirectory.path
            }
        }

        switch scope {
        case .user:
            print("Registered appshots as a user-scoped Claude MCP server.")
        case .project:
            print("Registered appshots as a project-scoped Claude MCP server at \(projectDirectory?.path ?? "").")
        }
    }

    private static func uninstall(arguments: [String], store: AppshotSettingsStore, registrar: ClaudeMCPRegistrar) throws {
        let scope = try resolveScope(arguments: arguments, store: store)
        let projectDirectory = resolveProjectDirectory(arguments: arguments, store: store)

        if CLIOptions.isDryRun(arguments) {
            print("[dry-run] would remove the \(scope.rawValue)-scoped appshots Claude MCP registration:")
            print("          claude mcp remove appshots -s \(scope.rawValue)")
            return
        }

        do {
            try registrar.disableSynchronously(scope: scope, projectDirectory: projectDirectory)
        } catch let error as MCPError {
            throw CLIError(message: error.errorDescription ?? "MCP removal failed.", exitCode: 1)
        }
        print("Removed the \(scope.rawValue)-scoped appshots Claude MCP registration.")
    }

    private static func status(arguments: [String], store: AppshotSettingsStore, registrar: ClaudeMCPRegistrar) throws {
        let projectDirectory = resolveProjectDirectory(arguments: arguments, store: store)
        let environment = registrar.environmentSynchronously()
        let status = registrar.statusSynchronously(projectDirectory: projectDirectory)

        if CLIOptions.wantsJSON(arguments) {
            let payload = MCPStatusReport(
                claudeFound: environment.claudeFound,
                claudePath: environment.claudePath,
                helperPath: environment.helperPath,
                helperExists: environment.helperExists,
                registration: describe(status)
            )
            if let line = try? AppshotJSON.string(payload) { print(line) }
            return
        }

        print("claude CLI: \(environment.claudeFound ? (environment.claudePath ?? "found") : "not found")")
        print("helper: \(environment.helperPath ?? "unresolved") (\(environment.helperExists ? "exists" : "missing"))")
        print("registration: \(describe(status))")
    }

    // MARK: - Resolution

    private static func resolveScope(arguments: [String], store: AppshotSettingsStore) throws -> MCPScope {
        let raw = CLIOptions.string(arguments, name: "--scope") ?? store.load().mcpDefaultScope
        guard let scope = MCPScope(rawValue: raw.lowercased()) else {
            throw CLIError(
                message: "Invalid scope '\(raw)': expected one of \(MCPScope.allCases.map(\.rawValue).joined(separator: ", ")).",
                exitCode: 2
            )
        }
        return scope
    }

    private static func resolveProjectDirectory(arguments: [String], store: AppshotSettingsStore) -> URL? {
        if let explicit = CLIOptions.string(arguments, name: "--project") {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
            }
        }
        if let stored = store.load().mcpLastProjectDirectory, stored.isEmpty == false {
            return URL(fileURLWithPath: stored)
        }
        return nil
    }

    private static func describe(_ status: MCPStatus) -> String {
        switch status {
        case .notEnabled:
            return "not enabled"
        case .enabledUser:
            return "enabled (user scope)"
        case let .enabledProject(path):
            return "enabled (project scope: \(path))"
        case let .error(message):
            return "error: \(message)"
        }
    }
}

private struct MCPStatusReport: Encodable {
    var claudeFound: Bool
    var claudePath: String?
    var helperPath: String?
    var helperExists: Bool
    var registration: String
}
