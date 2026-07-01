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
