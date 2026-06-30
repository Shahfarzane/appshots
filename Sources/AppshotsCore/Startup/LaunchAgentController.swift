import Foundation

/// Manages the headless-daemon launchd LaunchAgent — the `appshotsctl daemon`
/// hot-key host that runs without the GUI app.
///
/// This is the pure, testable half of the launch-at-login feature. It knows how
/// to render the `.plist`, write/remove it, and drive `launchctl` via `Process`;
/// it deliberately does **not** know about `SMAppService` (the GUI login item),
/// which lives in the app target.
///
/// The controller is keyed on an injectable ``launchAgentsDirectory`` and
/// ``programPath`` so tests can point it at a temp directory and inspect the
/// rendered plist without ever writing into the real `~/Library/LaunchAgents`
/// or shelling out to `launchctl`. The plist generator (``plistContents()``)
/// and the file step (``writePlist()``) are separate from the `launchctl`
/// bootstrap/bootout, so the plist output can be exercised in isolation.
public struct LaunchAgentController: Sendable {
    /// The launchd job label, matching `Sources/AppshotsCLI`'s `daemon` host.
    public static let label = "ceo.nerd.appshots.cli.daemon"

    /// Directory the `.plist` lives in (defaults to `~/Library/LaunchAgents`).
    public let launchAgentsDirectory: URL

    /// Directory the daemon's stdout/stderr logs are written to (defaults to
    /// `~/.appshots`, matching the rest of the on-disk store).
    public let logDirectory: URL

    /// Resolved path to the `appshotsctl` binary the agent runs. Defaults to the
    /// running executable (via ``ClaudeMCPRegistrar/selfExecutableHelperURL()``);
    /// `nil` when it cannot be resolved, in which case ``install()`` throws.
    public let programPath: URL?

    public init(
        launchAgentsDirectory: URL = LaunchAgentController.defaultLaunchAgentsDirectory,
        logDirectory: URL = LaunchAgentController.defaultLogDirectory,
        programPath: URL? = ClaudeMCPRegistrar.selfExecutableHelperURL()
    ) {
        self.launchAgentsDirectory = launchAgentsDirectory
        self.logDirectory = logDirectory
        self.programPath = programPath
    }

    /// The default user LaunchAgents directory.
    public static var defaultLaunchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    /// The default log directory (`~/.appshots`).
    public static var defaultLogDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".appshots", isDirectory: true)
    }

    /// The on-disk `.plist` path for the agent.
    public var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.label).plist", isDirectory: false)
    }

    /// Standard-out log path for the daemon.
    public var standardOutPath: String {
        logDirectory.appendingPathComponent("daemon.out.log", isDirectory: false).path
    }

    /// Standard-error log path for the daemon.
    public var standardErrorPath: String {
        logDirectory.appendingPathComponent("daemon.err.log", isDirectory: false).path
    }

    // MARK: - Plist rendering (pure)

    /// Renders the LaunchAgent property list as XML. Pure: depends only on its
    /// arguments, so it is fully testable without touching the filesystem.
    public static func plistContents(programPath: String, logDirectory: URL) -> String {
        let outPath = logDirectory.appendingPathComponent("daemon.out.log", isDirectory: false).path
        let errPath = logDirectory.appendingPathComponent("daemon.err.log", isDirectory: false).path
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(xmlEscape(label))</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(xmlEscape(programPath))</string>
                <string>daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>StandardOutPath</key>
            <string>\(xmlEscape(outPath))</string>
            <key>StandardErrorPath</key>
            <string>\(xmlEscape(errPath))</string>
        </dict>
        </plist>

        """
    }

    /// Renders the plist for this instance's resolved ``programPath``.
    public func plistContents() throws -> String {
        guard let programPath else { throw LaunchAgentError.programPathUnavailable }
        return Self.plistContents(programPath: programPath.path, logDirectory: logDirectory)
    }

    // MARK: - File step (separable from launchctl)

    /// Whether the agent's `.plist` exists on disk.
    public func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Writes the rendered plist to ``plistURL`` (creating directories as needed)
    /// and returns its URL. Does not invoke `launchctl`.
    @discardableResult
    public func writePlist() throws -> URL {
        let contents = try plistContents()
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        try contents.data(using: .utf8)?.write(to: plistURL, options: .atomic)
        return plistURL
    }

    /// Removes the agent's `.plist` if present. Does not invoke `launchctl`.
    public func removePlist() throws {
        guard isInstalled() else { return }
        try FileManager.default.removeItem(at: plistURL)
    }

    // MARK: - launchctl

    /// Writes the plist, then bootstraps the agent into the GUI domain so it
    /// starts immediately (and on every subsequent login).
    public func install() throws {
        let url = try writePlist()
        AppLog.startup.notice("installing LaunchAgent label=\(Self.label, privacy: .public)")
        // Idempotent: boot out a previously loaded agent first so a second
        // `startup enable` does not fail on an already-loaded service.
        try? runLaunchctl(["bootout", serviceTarget])
        try runLaunchctl(["bootstrap", domainTarget, url.path])
    }

    /// Boots the agent out of the GUI domain, then removes the plist.
    public func uninstall() throws {
        AppLog.startup.notice("uninstalling LaunchAgent label=\(Self.label, privacy: .public)")
        // Best-effort bootout: a not-loaded agent is fine to remove anyway.
        try? runLaunchctl(["bootout", serviceTarget])
        try removePlist()
    }

    /// The launchd domain target for the current user's GUI session.
    public var domainTarget: String {
        "gui/\(getuid())"
    }

    /// The fully qualified service target (`gui/<uid>/<label>`).
    public var serviceTarget: String {
        "\(domainTarget)/\(Self.label)"
    }

    // MARK: - Process plumbing

    private struct LaunchctlResult {
        let exitCode: Int32
        let standardOutput: String
        let standardError: String
    }

    private func runLaunchctl(_ arguments: [String]) throws {
        let result = try launchctl(arguments)
        guard result.exitCode == 0 else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchAgentError.launchctlFailed(
                command: "launchctl \(arguments.joined(separator: " "))",
                exitCode: result.exitCode,
                message: message.isEmpty ? result.standardOutput : message
            )
        }
    }

    private func launchctl(_ arguments: [String]) throws -> LaunchctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return LaunchctlResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Errors raised while installing or removing the headless LaunchAgent.
public enum LaunchAgentError: Error, CustomStringConvertible, Sendable {
    /// The `appshotsctl` binary path could not be resolved.
    case programPathUnavailable
    /// A `launchctl` invocation exited non-zero.
    case launchctlFailed(command: String, exitCode: Int32, message: String)

    public var description: String {
        switch self {
        case .programPathUnavailable:
            "Could not resolve the appshotsctl binary path for the LaunchAgent."
        case let .launchctlFailed(command, exitCode, message):
            "`\(command)` failed (exit \(exitCode)): \(message)"
        }
    }
}
