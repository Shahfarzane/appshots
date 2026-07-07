import AppKit
import AppshotsCore
import Foundation

enum AppshotsCLI {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            try run(arguments: arguments)
        } catch let error as CLIError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            Foundation.exit(Int32(error.exitCode))
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String]) throws {
        let command = arguments.first ?? "help"
        let rest = Array(arguments.dropFirst())
        let store = AppshotStore()

        // Per-subcommand help: `appshotsctl <command> --help` / `-h`.
        if command != "help", command != "--help", command != "-h",
           rest.contains("--help") || rest.contains("-h") {
            print(CommandHelp.text(for: command))
            return
        }

        switch command {
        case "capture":
            let mode = outputMode(from: rest)
            // The event-streaming capture paths are frontmost-only, so reject
            // `--app` with them rather than silently capturing the frontmost app.
            if rest.contains("--app"), mode == .events || mode == .eventStream {
                throw CLIError(message: "--app is not supported with --events / --event-stream output.", exitCode: 2)
            }
            if rest.contains("--events"), rest.contains("--timings") {
                try printCaptureEventsWithTimings(store: store, arguments: rest)
            } else if mode == .eventStream {
                try printCaptureEventStream(
                    timeoutSeconds: CLIOptions.double(rest, name: "--timeout-seconds") ?? AppshotCaptureConfiguration.default.timeoutSeconds,
                    arguments: rest
                )
            } else if mode == .events {
                do {
                    try printJSON(AppshotCaptureService.captureFrontmostApplicationWithEvents())
                } catch let error as AppshotCaptureEventError {
                    try printJSON(error.events)
                    throw CLIError(message: error.localizedDescription, exitCode: 1)
                }
            } else {
                let record = try captureRecord(arguments: rest)
                maybeCopy(record: record, arguments: rest)
                if rest.contains("--timings") {
                    let metrics = try store.captureMetrics(for: record)
                    try printJSON(TimingCaptureResult(
                        record: record,
                        metrics: metrics,
                        summary: TimingSummary(metrics: metrics)
                    ))
                } else {
                    try printRecordOutput(record, mode: mode, store: store)
                }
            }
        case "config":
            try ConfigCommand.run(arguments: rest, store: seededSettingsStore())
        case "trigger":
            try TriggerCommand.run(arguments: rest, store: seededSettingsStore())
        case "sound":
            try SoundCommand.run(arguments: rest, store: seededSettingsStore())
        case "update":
            try UpdateCommand.run(arguments: rest, store: seededSettingsStore())
        case "startup":
            try StartupCommand.run(arguments: rest, store: seededSettingsStore())
        case "onboarding":
            try OnboardingCommand.run(arguments: rest, store: store, settingsStore: seededSettingsStore())
        case "benchmark":
            try runBenchmark(arguments: rest, store: store)
        case "latest":
            guard let record = store.latestCapture() else {
                throw CLIError(message: "No appshots captured yet.", exitCode: 2)
            }
            try printRecordOutput(record, mode: outputMode(from: rest), store: store)
        case "list":
            // Clamp: `prefix(_:)` traps on a negative count (the MCP server
            // clamps for the same reason).
            let limit = max(0, CLIOptions.integer(rest, name: "--limit") ?? 20)
            try printJSON(Array(store.allCaptures().prefix(limit)))
        case "search":
            // Build the query from positional tokens only — skipping flags AND
            // the value following a value-taking flag — so `search safari
            // --limit 5` searches for "safari", not "safari 5".
            var queryTokens: [String] = []
            var index = rest.startIndex
            while index < rest.endIndex {
                let token = rest[index]
                if token.hasPrefix("--") {
                    if token == "--limit" { index = rest.index(after: index) }
                } else {
                    queryTokens.append(token)
                }
                index = rest.index(after: index)
            }
            let query = queryTokens.joined(separator: " ")
            guard query.isEmpty == false else {
                throw CLIError(message: "Usage: appshotsctl search <query> [--limit N]", exitCode: 2)
            }
            let limit = max(0, CLIOptions.integer(rest, name: "--limit") ?? 20)
            try printJSON(store.searchCaptures(query: query, limit: limit))
        case "delete":
            guard let id = rest.first else {
                throw CLIError(message: "Usage: appshotsctl delete <capture-id>", exitCode: 2)
            }
            let deleted = try store.deleteCapture(id: id)
            if deleted {
                print("Deleted \(id)")
            } else {
                throw CLIError(message: "Capture not found: \(id)", exitCode: 2)
            }
        case "doctor":
            try runDoctor(store: store)
        case "mcp":
            // Only a bare `mcp` starts the blocking stdio server; anything else
            // routes to MCPCommand so a typo (`mcp instal`) hits its usage
            // error instead of silently hanging on stdin.
            if rest.isEmpty {
                try AppshotMCPServer(store: store).run()
            } else {
                try MCPCommand.run(arguments: rest, store: seededSettingsStore())
            }
        case "daemon":
            // Hosts the headless AppKit run loop the global hot key needs; blocks
            // on NSApp.run(). The CLI entry runs on the main thread.
            MainActor.assumeIsolated {
                AppshotDaemon.run()
            }
        case "completion":
            try Completion.run(arguments: rest)
        case "help", "--help", "-h":
            if let topic = rest.first(where: { $0.hasPrefix("-") == false }) {
                print(CommandHelp.text(for: topic))
            } else {
                print(helpText)
            }
        case "version", "--version", "-V":
            print("appshotsctl \(version)")
        default:
            throw CLIError(message: "Unknown command: \(command)\n\n\(helpText)", exitCode: 2)
        }
    }

    /// The CLI version. Read from the embedded `Info.plist` section on a shipped
    /// binary; falls back to the marketing version for a bare `swift build`.
    private static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.3"
    }

    private static func printRecordOutput(
        _ record: AppshotRecord,
        mode: OutputMode,
        store: AppshotStore
    ) throws {
        let format: AppshotOutputFormat
        switch mode {
        case .prompt: format = .prompt
        case .image: format = .imagePath
        case .json: format = .json
        case .modelPrompt: format = .modelPrompt
        case .payload: format = .payload
        case .context: format = .context
        case .events: format = .events
        case .directory: format = .directory
        case .metadata: format = .metadata
        case .timings:
            print(try AppshotJSON.string(TimingSummary(metrics: try store.captureMetrics(for: record))))
            return
        case .eventStream:
            throw CLIError(message: "--event-stream is only supported with capture.", exitCode: 2)
        }

        do {
            print(try store.render(record, as: format))
        } catch let error as AppshotOutputError {
            throw CLIError(message: error.localizedDescription, exitCode: 2)
        }
    }

    /// Produces the capture record for the `capture` command: targets a specific
    /// app when `--app <bundle-or-name>` is present, otherwise the frontmost app.
    private static func captureRecord(arguments: [String]) throws -> AppshotRecord {
        // Distinguish "--app is absent" (capture frontmost) from "--app present
        // but missing its value" (a usage error). A bare `--app` must not
        // silently fall back to the frontmost app.
        if arguments.contains("--app") {
            guard let identifier = CLIOptions.string(arguments, name: "--app") else {
                throw CLIError(message: "--app requires a bundle id or app name.", exitCode: 2)
            }
            let target = try AppshotCaptureService.resolveTarget(matching: identifier)
            return try AppshotCaptureService.capture(target: target)
        }
        return try AppshotCaptureService.captureFrontmostApplication()
    }

    /// Copies the capture to the clipboard when `--copy` is passed or
    /// `copyOnCapture` is enabled in settings. Orthogonal to the output mode.
    private static func maybeCopy(record: AppshotRecord, arguments: [String]) {
        let shouldCopy = arguments.contains("--copy") || AppshotSettingsStore().load().copyOnCapture
        guard shouldCopy else { return }
        // The CLI is not an AppKit app; initialize the Cocoa machinery once so
        // the general pasteboard is available before writing to it.
        // `NSApplicationLoad` is imported under its Swift-private name.
        _ = __NSApplicationLoad()
        PasteboardWriter.copyAppshotMarkup(for: record)
    }

    /// Loads the shared settings store, seeding `config.json` from legacy
    /// preferences / defaults first so headless users always have a canonical file.
    private static func seededSettingsStore() -> AppshotSettingsStore {
        let settingsStore = AppshotSettingsStore()
        AppshotSettingsMigration.seedIfNeeded(store: settingsStore)
        return settingsStore
    }

    private static func runDoctor(store: AppshotStore) throws {
        let checks = AppshotDoctor.run(store: store)
        try printJSON(checks)
        if checks.contains(where: { $0.ok == false }) {
            Foundation.exit(1)
        }
    }

    private static func outputMode(from arguments: [String]) -> OutputMode {
        if arguments.contains("--image") { return .image }
        if arguments.contains("--json") { return .json }
        if arguments.contains("--model-prompt") { return .modelPrompt }
        if arguments.contains("--payload") { return .payload }
        if arguments.contains("--context") { return .context }
        if arguments.contains("--events") { return .events }
        if arguments.contains("--event-stream") { return .eventStream }
        if arguments.contains("--timings") { return .timings }
        if arguments.contains("--dir") { return .directory }
        if arguments.contains("--metadata") { return .metadata }
        return .prompt
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        print(try AppshotJSON.string(value))
    }

    /// Serialises NDJSON lines: `--event-stream` writes from the caller's
    /// thread, the engine's background delivery queue, and the timeout thread,
    /// so each line must land as a single locked write or a consumer can see
    /// two events spliced together.
    private static let jsonLineLock = NSLock()

    private static func printJSONLine<T: Encodable>(_ value: T) throws {
        var data = try AppshotJSON.lineEncoder.encode(value)
        data.append(UInt8(ascii: "\n"))
        jsonLineLock.lock()
        defer { jsonLineLock.unlock() }
        FileHandle.standardOutput.write(data)
    }

    private static func printCaptureEventStream(timeoutSeconds: Double, arguments: [String]) throws {
        let timeoutState = EventStreamTimeoutState()
        if timeoutSeconds > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                guard timeoutState.markTimedOut() else { return }
                do {
                    try printJSONLine(AppshotCaptureEvent(
                        status: .failed,
                        requestID: "timeout",
                        failureReason: "capture_timed_out"
                    ))
                } catch {
                    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                }
                FileHandle.standardError.write(Data(("Appshot capture timed out after \(Int(timeoutSeconds.rounded())) seconds.\n").utf8))
                Foundation.exit(1)
            }
        }

        do {
            let record = try AppshotCaptureService.captureFrontmostApplicationWithEventHandler { event in
                do {
                    try printJSONLine(event)
                } catch {
                    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                }
            }
            timeoutState.markCompleted()
            maybeCopy(record: record, arguments: arguments)
        } catch {
            timeoutState.markCompleted()
            throw CLIError(message: error.localizedDescription, exitCode: 1)
        }
    }

    private static func printCaptureEventsWithTimings(store: AppshotStore, arguments: [String]) throws {
        var events: [AppshotCaptureEvent] = []
        do {
            let record = try AppshotCaptureService.captureFrontmostApplicationWithEventHandler { event in
                events.append(event)
            }
            maybeCopy(record: record, arguments: arguments)
            let metrics = try store.captureMetrics(for: record)
            try printJSON(TimingEventResult(
                events: events,
                record: record,
                metrics: metrics,
                summary: TimingSummary(metrics: metrics)
            ))
        } catch let error as AppshotCaptureEventError {
            try printJSON(TimingEventResult(
                events: error.events,
                record: nil,
                metrics: nil,
                summary: nil
            ))
            throw CLIError(message: error.localizedDescription, exitCode: 1)
        }
    }

    private static func runBenchmark(arguments: [String], store: AppshotStore) throws {
        let count = CLIOptions.integer(arguments, name: "--count") ?? 10
        let warmup = CLIOptions.integer(arguments, name: "--warmup") ?? 2
        let target = try CLIOptions.string(arguments, name: "--app")
            .map(AppshotCaptureService.resolveTarget(matching:))
        guard count > 0, warmup >= 0 else {
            throw CLIError(message: "Usage: appshotsctl benchmark [--app BUNDLE_OR_NAME] [--count N] [--warmup N]", exitCode: 2)
        }

        if let target {
            AppshotCaptureService.prewarm(pid: target.pid)
        } else {
            AppshotCaptureService.prewarm()
        }
        for _ in 0..<warmup {
            if let target {
                _ = try AppshotCaptureService.capture(target: target)
            } else {
                _ = try AppshotCaptureService.captureFrontmostApplication()
            }
        }

        var samples: [BenchmarkSample] = []
        for index in 0..<count {
            let record = if let target {
                try AppshotCaptureService.capture(target: target)
            } else {
                try AppshotCaptureService.captureFrontmostApplication()
            }
            let metrics = try store.captureMetrics(for: record)
            samples.append(BenchmarkSample(
                iteration: index + 1,
                recordID: record.id,
                metrics: metrics
            ))
        }

        try printJSON(BenchmarkResult(samples: samples))
    }

    private static let helpText = """
    Usage: appshotsctl <command> [options]

    Global options:
      -h, --help           Show this help (or `help <command>` / `<command> --help`)
      --version            Print the appshotsctl version
      --json               Machine-readable output (config list, startup/mcp status)
      -n, --dry-run        Preview a state change without applying it (startup, mcp)

    Commands:
      capture              Capture the frontmost app and print appshot.md
      benchmark            Capture repeatedly and print phase p50/p95 timings
      latest               Print the latest appshot.md
      list [--limit N]     Print recent captures as JSON
      search <query>       Search indexed captures
      delete <id>          Delete a capture
      doctor               Check storage and latest capture health
      mcp                  Run the native stdio MCP server (no subcommand)
      daemon               Run the headless hot-key host (no GUI required)
      completion zsh|bash  Print a shell completion script

    Configuration commands (shared config.json + a running GUI live-reloads):
      config list [--json]         List all settings keys and current values
      config get <key>             Print one setting value
      config set <key> <value>     Validate and persist a setting
      config unset <key>           Reset a setting to its default
      config path                  Print the config.json path
      trigger get                  Print the capture trigger key codes + labels
      trigger set --preset P       Set trigger from a preset (option|command|shift)
      trigger set --keys 58,61     Set trigger from raw CGKeyCode CSV
      trigger reset                Reset the trigger to the default (58,61)
      sound enable|disable|status  Toggle / show the capture sound
      update auto on|off|status    Toggle / show Sparkle auto-update
      startup status               Show startup mode + LaunchAgent state
      startup enable [--headless|--gui]  Launch at login (default --headless)
      startup disable              Stop launching at login
      onboarding status            Report Accessibility + Screen Recording + onboarding
      mcp install [--scope S] [--project DIR]   Register this CLI as the Claude MCP server
      mcp uninstall [--scope S]    Remove the Claude MCP registration
      mcp status                   Show the Claude MCP registration state

    Capture options (capture, benchmark):
      --app BUNDLE_OR_NAME Target a running app by bundle id or name (else frontmost)
      --copy               Also copy the appshot + screenshot to the clipboard (capture)

    Benchmark options:
      --count N            Measured captures; defaults to 10
      --warmup N           Warmup captures before measuring; defaults to 2

    Output options for capture/latest:
      --image              Print screenshot path
      --json               Print metadata JSON
      --model-prompt       Print minimal model-facing appshot prompt
      --payload            Print JSON with model prompt, image path, image data URL, and metadata
      --context            Print first-class AppshotContext JSON
      --events             Print Appshot capture event JSON
      --event-stream       Print newline-delimited capture events as they are emitted
      --timings            Print capture metrics / timing summary
      --timeout-seconds N  Timeout for --event-stream; defaults to 120
      --dir                Print capture directory
      --metadata           Print metadata.json path
    """
}

private enum OutputMode {
    case prompt
    case image
    case json
    case modelPrompt
    case payload
    case context
    case events
    case eventStream
    case directory
    case metadata
    case timings
}

private struct TimingCaptureResult: Encodable {
    var record: AppshotRecord
    var metrics: AppshotCaptureMetrics
    var summary: TimingSummary
}

private struct TimingEventResult: Encodable {
    var events: [AppshotCaptureEvent]
    var record: AppshotRecord?
    var metrics: AppshotCaptureMetrics?
    var summary: TimingSummary?
}

private struct TimingSummary: Encodable {
    var requestID: String
    var axNodeCount: Int
    var screenshotBackend: String?
    var totalDurationMs: Double
    var phases: [String: Double]

    init(metrics: AppshotCaptureMetrics) {
        requestID = metrics.requestID
        axNodeCount = metrics.axNodeCount
        screenshotBackend = metrics.screenshotBackend
        totalDurationMs = metrics.phases.map { $0.startedAtOffsetMs + $0.durationMs }.max() ?? 0
        var latestByPhase: [String: Double] = [:]
        for phase in metrics.phases {
            latestByPhase[phase.name] = phase.durationMs
        }
        phases = latestByPhase
    }
}

private struct BenchmarkSample: Encodable {
    var iteration: Int
    var recordID: String
    var metrics: AppshotCaptureMetrics
}

private struct BenchmarkResult: Encodable {
    var samples: [BenchmarkSample]
    var phaseStats: [String: BenchmarkPhaseStats]

    init(samples: [BenchmarkSample]) {
        self.samples = samples
        var valuesByPhase: [String: [Double]] = [:]
        for sample in samples {
            for phase in sample.metrics.phases {
                valuesByPhase[phase.name, default: []].append(phase.durationMs)
            }
        }
        phaseStats = valuesByPhase.mapValues(BenchmarkPhaseStats.init(values:))
    }
}

private struct BenchmarkPhaseStats: Encodable {
    var count: Int
    var p50Ms: Double
    var p95Ms: Double

    init(values: [Double]) {
        let sorted = values.sorted()
        count = sorted.count
        p50Ms = Self.percentile(sorted, 0.50)
        p95Ms = Self.percentile(sorted, 0.95)
    }

    private static func percentile(_ sorted: [Double], _ percentile: Double) -> Double {
        guard sorted.isEmpty == false else { return 0 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * percentile).rounded())))
        return sorted[index]
    }
}

/// A user-facing CLI failure. `message` is written to stderr and the process
/// exits with `exitCode` (0 ok / 1 failure / 2 usage + not-found). Shared across
/// all `appshotsctl` subcommand files.
struct CLIError: Error {
    var message: String
    var exitCode: Int
}

private final class EventStreamTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func markCompleted() {
        lock.withLock {
            finished = true
        }
    }

    func markTimedOut() -> Bool {
        lock.withLock {
            guard finished == false else { return false }
            finished = true
            return true
        }
    }
}

AppshotsCLI.main()
