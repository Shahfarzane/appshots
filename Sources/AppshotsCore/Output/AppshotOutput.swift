import ApplicationServices
import CoreGraphics
import Foundation

/// The set of string-rendered output formats shared by the CLI output flags and
/// the MCP `format` argument. `codex` and `eventStream` are intentionally absent:
/// they return non-string content (image item / newline-delimited stream) and
/// stay special-cased at their call sites.
public enum AppshotOutputFormat: String {
    case prompt
    case modelPrompt
    case json
    case payload
    case context
    case events
    case directory
    case imagePath
    case metadata
}

/// Error thrown by `AppshotStore.render(_:as:)` when a format cannot be produced.
public enum AppshotOutputError: LocalizedError {
    case missingScreenshot(captureID: String)

    public var errorDescription: String? {
        switch self {
        case .missingScreenshot(let captureID):
            return "Capture has no screenshot: \(captureID)"
        }
    }
}

/// Shared JSON encoders for CLI and MCP output, so both targets emit
/// byte-identical JSON. `encoder` matches the CLI `printJSON` / MCP `jsonText`
/// pretty config; `lineEncoder` matches the CLI `printJSONLine` config used by
/// the newline-delimited capture event stream.
public enum AppshotJSON {
    private static let fractionalSecondsStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSecondsStyle = Date.ISO8601FormatStyle()

    /// ISO-8601 with fractional (millisecond) seconds. Whole-second encoding
    /// floor-truncated `createdAt`/`startedAt` by up to a second, so records
    /// didn't round-trip equal and `appendMetricPhase` offsets were skewed by
    /// up to ~1000ms against the recorder's own phase offsets in the same file.
    public static var dateEncodingStrategy: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalSecondsStyle.format(date))
        }
    }

    /// Accepts both fractional and whole-second ISO-8601, so files written by
    /// older builds (and by hand) keep decoding.
    public static var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = (try? fractionalSecondsStyle.parse(string)) ?? (try? wholeSecondsStyle.parse(string)) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO-8601 date: \(string)"
            )
        }
    }

    /// Pretty, deterministic JSON: `[.prettyPrinted, .sortedKeys]` + ISO-8601 dates.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = dateEncodingStrategy
        return encoder
    }

    /// Single-line, deterministic JSON: `[.sortedKeys]` + ISO-8601 dates.
    public static var lineEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = dateEncodingStrategy
        return encoder
    }

    /// The matching decoder (tolerant ISO-8601 dates).
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecodingStrategy
        return decoder
    }

    /// Encodes `value` with the pretty `encoder` and returns it as a UTF-8 string.
    public static func string<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

/// A single Appshots health check result. Encodes to the same `{detail, name, ok}`
/// JSON shape the CLI `doctor` command and the `doctor_appshots` MCP tool emit.
public struct AppshotHealthCheck: Codable {
    public var name: String
    public var ok: Bool
    public var detail: String

    public init(name: String, ok: Bool, detail: String) {
        self.name = name
        self.ok = ok
        self.detail = detail
    }
}

/// Shared health-check runner used by both the CLI `doctor` command and the
/// `doctor_appshots` MCP tool. The check list, names, detail strings, predicates,
/// and order are the wire contract — keep them identical across both call sites.
public enum AppshotDoctor {
    public static func run(store: AppshotStore) -> [AppshotHealthCheck] {
        let latest = store.latestCapture()
        return [
            AppshotHealthCheck(name: "accessibility_permission", ok: AXIsProcessTrusted(), detail: "System Settings > Privacy & Security > Accessibility"),
            AppshotHealthCheck(name: "screen_recording_permission", ok: CGPreflightScreenCaptureAccess(), detail: "System Settings > Privacy & Security > Screen & System Audio Recording"),
            AppshotHealthCheck(name: "storage_root", ok: FileManager.default.fileExists(atPath: store.rootURL.path), detail: store.rootURL.path),
            AppshotHealthCheck(name: "index", ok: FileManager.default.fileExists(atPath: store.indexURL.path), detail: store.indexURL.path),
            AppshotHealthCheck(name: "latest_capture", ok: latest != nil, detail: latest?.id ?? "none"),
            AppshotHealthCheck(name: "latest_prompt", ok: latest.map { FileManager.default.fileExists(atPath: $0.appshotTextPath) } ?? false, detail: latest?.appshotTextPath ?? "none"),
            AppshotHealthCheck(name: "latest_screenshot", ok: latest?.screenshotPath.map(FileManager.default.fileExists(atPath:)) ?? false, detail: latest?.screenshotPath ?? "none"),
        ]
    }
}

extension AppshotStore {
    /// Renders `record` to the string each call site currently produces for the
    /// given format. Behavior is byte-identical to the existing CLI/MCP code.
    public func render(_ record: AppshotRecord, as format: AppshotOutputFormat) throws -> String {
        switch format {
        case .prompt:
            return (try? String(contentsOf: record.appshotTextURL, encoding: .utf8)) ?? record.referenceText
        case .modelPrompt:
            return try modelPrompt(for: record)
        case .json:
            return try AppshotJSON.string(record)
        case .payload:
            return try AppshotJSON.string(try payload(for: record))
        case .context:
            return try AppshotJSON.string(try appshotContext(for: record))
        case .events:
            return try AppshotJSON.string([try completedEvent(for: record, includeImageData: false)])
        case .directory:
            return record.directoryPath
        case .imagePath:
            guard let path = record.screenshotPath else {
                throw AppshotOutputError.missingScreenshot(captureID: record.id)
            }
            return path
        case .metadata:
            return record.metadataPath
        }
    }
}
