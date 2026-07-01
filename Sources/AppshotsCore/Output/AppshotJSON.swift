import Foundation

/// Shared JSON encoders for CLI and MCP output, so both targets emit
/// byte-identical JSON. `encoder` matches the CLI `printJSON` / MCP `jsonText`
/// pretty config; `lineEncoder` matches the CLI `printJSONLine` config used by
/// the newline-delimited capture event stream.
public enum AppshotJSON {
    /// Pretty, deterministic JSON: `[.prettyPrinted, .sortedKeys]` + ISO-8601 dates.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Single-line, deterministic JSON: `[.sortedKeys]` + ISO-8601 dates.
    public static var lineEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Encodes `value` with the pretty `encoder` and returns it as a UTF-8 string.
    public static func string<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
