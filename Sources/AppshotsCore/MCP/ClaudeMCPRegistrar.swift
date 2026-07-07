import Foundation

/// Scope for the Claude Code MCP registration.
public enum MCPScope: String, CaseIterable, Identifiable, Sendable {
    case user
    case project

    public var id: String { rawValue }

    /// Flag passed to `claude mcp add/remove -s <flag>`.
    var claudeFlag: String { rawValue }

    public var displayName: String {
        switch self {
        case .user: return "User (global)"
        case .project: return "Project"
        }
    }
}

/// Resolved state of the Claude Code `appshots` MCP server registration.
public enum MCPStatus: Equatable, Sendable {
    case notEnabled
    case enabledUser
    case enabledProject(path: String)
    case error(String)
}

/// Snapshot of the tools the manager depends on (helper binary + claude CLI).
public struct MCPEnvironmentInfo: Sendable {
    public let helperPath: String?
    public let helperExists: Bool
    public let claudePath: String?
    public let claudeFound: Bool
}

public enum MCPError: LocalizedError {
    case claudeNotFound
    case helperNotFound
    case projectDirectoryMissing
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude Code CLI not found. Install Claude Code, then try again."
        case .helperNotFound:
            return "The appshotsctl helper could not be located."
        case .projectDirectoryMissing:
            return "Choose a project folder before enabling project scope."
        case .commandFailed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "The Claude Code command failed." : trimmed
        }
    }
}

/// Manages the in-app "Enable MCP" flow for Claude Code.
///
/// All `Process` work runs off the main thread on a private queue; the async
/// surface lets callers `await` results and hop back to `@MainActor` for UI.
public final class ClaudeMCPRegistrar: Sendable {
    static let registeredServerName = "appshots"

    private let queue = DispatchQueue(label: "ceo.nerd.appshots.mcp", qos: .userInitiated)

    /// When set, this exact binary is registered as the MCP helper instead of
    /// resolving the GUI app's bundled `Contents/Helpers/appshotsctl`. The CLI
    /// passes ``selfExecutableHelperURL()`` so it registers its own binary.
    private let helperURLOverride: URL?

    public init(helperURLOverride: URL? = nil) {
        self.helperURLOverride = helperURLOverride
    }

    // MARK: - Public async API

    public func environment() async -> MCPEnvironmentInfo {
        await run { manager in manager.resolveEnvironment() }
    }

    public func status(projectDirectory: URL? = nil) async -> MCPStatus {
        await run { manager in manager.resolveStatus(projectDirectory: projectDirectory) }
    }

    public func enableUser() async throws {
        try await runThrowing { manager in
            try manager.add(scope: .user, directory: nil)
        }
    }

    public func enableProject(directory: URL) async throws {
        try await runThrowing { manager in
            try manager.add(scope: .project, directory: directory)
        }
    }

    public func disable(scope: MCPScope, projectDirectory: URL? = nil) async throws {
        try await runThrowing { manager in
            try manager.remove(scope: scope, directory: projectDirectory, ignoreMissing: false)
        }
    }

    // MARK: - Synchronous API (CLI)

    /// Synchronous variants for the one-shot `appshotsctl mcp …` commands, which
    /// run on the CLI's own thread and have no actor to hop back to. They invoke
    /// the same private primitives as the async surface above.

    public func environmentSynchronously() -> MCPEnvironmentInfo {
        resolveEnvironment()
    }

    public func statusSynchronously(projectDirectory: URL? = nil) -> MCPStatus {
        resolveStatus(projectDirectory: projectDirectory)
    }

    public func enableUserSynchronously() throws {
        try add(scope: .user, directory: nil)
    }

    public func enableProjectSynchronously(directory: URL) throws {
        try add(scope: .project, directory: directory)
    }

    public func disableSynchronously(scope: MCPScope, projectDirectory: URL? = nil) throws {
        try remove(scope: scope, directory: projectDirectory, ignoreMissing: false)
    }

    // MARK: - Helper-path resolution for self-registration

    /// The helper binary to register when the *current* process is itself
    /// `appshotsctl` (e.g. the CLI registering its own binary as the MCP
    /// server). Unlike `resolveHelperURL`, which prefers the GUI app's bundled
    /// `Contents/Helpers/appshotsctl`, this returns the running executable's
    /// own path so a standalone CLI can wire itself up as the MCP server without
    /// a surrounding `.app` bundle.
    ///
    /// Deliberately does **not** resolve symlinks: a Homebrew install exposes a
    /// stable `/opt/homebrew/bin/appshotsctl` symlink into the versioned Cellar,
    /// and both the MCP registration and the LaunchAgent `ProgramArguments[0]`
    /// must keep pointing at that stable path so they survive `brew upgrade`.
    public static func selfExecutableHelperURL() -> URL? {
        Bundle.main.executableURL?.standardizedFileURL
    }

    // MARK: - Off-main dispatch helpers

    private func run<T: Sendable>(_ work: @Sendable @escaping (ClaudeMCPRegistrar) -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work(self)) }
        }
    }

    private func runThrowing<T: Sendable>(_ work: @Sendable @escaping (ClaudeMCPRegistrar) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work(self)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    // MARK: - Environment resolution

    private func resolveEnvironment() -> MCPEnvironmentInfo {
        let helper = resolveHelperURL()
        let claude = resolveClaudeURL()
        return MCPEnvironmentInfo(
            helperPath: helper?.path,
            helperExists: helper.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
            claudePath: claude?.path,
            claudeFound: claude != nil
        )
    }

    /// Best candidate for the bundled helper. Prefers an existing file but
    /// always returns the most likely path so the UI can surface it.
    private func resolveHelperURL() -> URL? {
        // An explicit override (e.g. the CLI registering its own binary) wins
        // over the GUI bundle / build-product discovery below.
        if let helperURLOverride {
            return helperURLOverride
        }

        var candidates: [URL] = []

        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/appshotsctl")
        candidates.append(bundled)

        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("appshotsctl"))
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent(".build/debug/appshotsctl"))
        candidates.append(cwd.appendingPathComponent(".build/release/appshotsctl"))

        if let existing = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existing
        }
        return candidates.first
    }

    private func existingHelperURL() throws -> URL {
        guard let helper = resolveHelperURL(),
              FileManager.default.fileExists(atPath: helper.path) else {
            throw MCPError.helperNotFound
        }
        return helper
    }

    /// Resolves the `claude` CLI from a GUI app, where `PATH` is minimal.
    private func resolveClaudeURL() -> URL? {
        if let resolved = runProcess(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "command -v claude"]
        ) {
            let path = resolved.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            URL(fileURLWithPath: "/usr/bin/claude")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func resolveClaudeURLOrThrow() throws -> URL {
        guard let claude = resolveClaudeURL() else { throw MCPError.claudeNotFound }
        return claude
    }

    // MARK: - Commands

    private func add(scope: MCPScope, directory: URL?) throws {
        if scope == .project, directory == nil { throw MCPError.projectDirectoryMissing }
        let claude = try resolveClaudeURLOrThrow()
        let helper = try existingHelperURL()

        // Idempotent: clear any prior registration in this scope first.
        try remove(scope: scope, directory: directory, ignoreMissing: true)

        let arguments = ["mcp", "add", Self.registeredServerName, "-s", scope.claudeFlag, "--", helper.path, "mcp"]
        guard let result = runProcess(executable: claude, arguments: arguments, currentDirectory: directory) else {
            throw MCPError.commandFailed("Could not launch the Claude Code CLI.")
        }
        if result.exitCode != 0 {
            throw MCPError.commandFailed(result.failureMessage)
        }
    }

    private func remove(scope: MCPScope, directory: URL?, ignoreMissing: Bool) throws {
        let claude = try resolveClaudeURLOrThrow()
        let arguments = ["mcp", "remove", Self.registeredServerName, "-s", scope.claudeFlag]
        guard let result = runProcess(executable: claude, arguments: arguments, currentDirectory: directory) else {
            if ignoreMissing { return }
            throw MCPError.commandFailed("Could not launch the Claude Code CLI.")
        }
        if result.exitCode != 0 {
            let combined = result.failureMessage.lowercased()
            let notPresent = combined.contains("no mcp")
                || combined.contains("not found")
                || combined.contains("does not exist")
                || combined.contains("no server")
            if ignoreMissing || notPresent { return }
            throw MCPError.commandFailed(result.failureMessage)
        }
    }

    private func resolveStatus(projectDirectory: URL?) -> MCPStatus {
        guard resolveClaudeURL() != nil else { return .error("Claude Code CLI not found") }
        guard let result = runProcess(
            executable: try? resolveClaudeURLOrThrow(),
            arguments: ["mcp", "get", Self.registeredServerName],
            currentDirectory: projectDirectory
        ) else {
            return .error("Failed to query Claude Code")
        }

        if result.exitCode != 0 {
            return .notEnabled
        }

        let output = result.standardOutput
        // Parse the `Scope:` line specifically. Substring-matching the whole
        // output misclassifies: a user-scoped server prints "Scope: User config
        // (available in all your projects)", whose "projects" would match a
        // naive project check, and a helper path can contain either word.
        let scopeValue = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.lowercased().hasPrefix("scope:") }
            .map { $0.dropFirst("scope:".count).trimmingCharacters(in: .whitespaces).lowercased() }
        if let scopeValue {
            if scopeValue.hasPrefix("user") {
                return .enabledUser
            }
            // "Local" registrations are project-specific too; report them with
            // the project path like project scope.
            if scopeValue.hasPrefix("project") || scopeValue.hasPrefix("local") {
                let path = projectPath(from: output) ?? projectDirectory?.path ?? ""
                return .enabledProject(path: path)
            }
        }
        // Registered but scope unrecognised — treat as user-level.
        return .enabledUser
    }

    private func projectPath(from output: String) -> String? {
        guard let range = output.range(of: "file:", options: .caseInsensitive) else { return nil }
        let tail = output[range.upperBound...]
        let stopCharacters = CharacterSet(charactersIn: ")\n\r")
        var path = ""
        for character in tail {
            if let scalar = character.unicodeScalars.first, stopCharacters.contains(scalar) { break }
            path.append(character)
        }
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Process execution (synchronous, called only on `queue`)

    private struct ProcessResult {
        let exitCode: Int32
        let standardOutput: String
        let standardError: String

        var failureMessage: String {
            let error = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return error.isEmpty ? standardOutput : error
        }
    }

    private func runProcess(executable: URL?, arguments: [String], currentDirectory: URL? = nil) -> ProcessResult? {
        guard let executable else { return nil }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.environment = augmentedEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // Drain both pipes concurrently: `claude` can emit >64KB of stderr
        // (Node warnings, stack traces) and would deadlock a sequential
        // read-stdout-then-stderr parent.
        let outputDrain = PipeDrain(outputPipe.fileHandleForReading)
        let errorDrain = PipeDrain(errorPipe.fileHandleForReading)
        let outputData = outputDrain.waitForData()
        let errorData = errorDrain.waitForData()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }

    /// GUI apps inherit a minimal `PATH`; widen it so `claude` can find `node`.
    private func augmentedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = [
            "\(home)/.claude/local",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let current = environment["PATH"] ?? ""
        let merged = (current.split(separator: ":").map(String.init) + extra)
        var seen = Set<String>()
        let deduped = merged.filter { seen.insert($0).inserted && !$0.isEmpty }
        environment["PATH"] = deduped.joined(separator: ":")
        return environment
    }
}
