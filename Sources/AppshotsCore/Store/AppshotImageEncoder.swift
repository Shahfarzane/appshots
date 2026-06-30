import AppKit
import Foundation

/// Error thrown when an image exceeds the inline-content size guard. Its
/// `localizedDescription` matches the message the MCP image content path emits.
public enum AppshotImageError: LocalizedError {
    case tooLargeForInlineContent

    public var errorDescription: String? {
        switch self {
        case .tooLargeForInlineContent:
            return "Appshot screenshot is too large to return as MCP image content."
        }
    }
}

extension AppshotStore {
    public static let maxInlineImageBytes = 25 * 1024 * 1024

    /// Reads the PNG at `path`, enforcing the `maxInlineImageBytes` guard with
    /// both the on-disk size and the in-memory `Data` length, and returns the
    /// base64-encoded bytes (no data-URL prefix). Throws
    /// `AppshotImageError.tooLargeForInlineContent` when either check exceeds the
    /// limit — the exact message the MCP image content path uses.
    public func inlinePNG(at path: String) throws -> String {
        let attributes = try fileManager.attributesOfItem(atPath: path)
        if let bytes = (attributes[.size] as? NSNumber)?.intValue, bytes > Self.maxInlineImageBytes {
            throw AppshotImageError.tooLargeForInlineContent
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        if data.count > Self.maxInlineImageBytes {
            throw AppshotImageError.tooLargeForInlineContent
        }
        return data.base64EncodedString()
    }

    func pngDataURL(from screenshotURL: URL) throws -> String {
        "data:image/png;base64,\(try inlinePNG(at: screenshotURL.path))"
    }

    func appIconDataURL(for record: AppshotRecord) -> String? {
        guard let bitmap = appIconBitmap(forBundleID: record.bundleID),
              let pngData = bitmap.representation(using: .png, properties: [:]),
              pngData.count <= Self.maxInlineImageBytes
        else {
            return nil
        }

        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }

    /// PNG data URL for the rendered transition-snapshot card, if one exists on disk
    /// and fits the inline-size guard. Mirrors `imageDataURL` but sources the polished
    /// transition card rather than the raw screenshot. Returns nil when absent or
    /// unreadable so callers can fall back to the screenshot data URL.
    func transitionSnapshotDataURL(for record: AppshotRecord) -> String? {
        guard let transitionURL = record.transitionSnapshotURL,
              fileManager.fileExists(atPath: transitionURL.path)
        else {
            return nil
        }

        return try? pngDataURL(from: transitionURL)
    }

    /// Best-effort app-icon `CGImage` for the offscreen transition-snapshot
    /// renderer. Mirrors `appIconDataURL(for:)` but returns a `CGImage` and is keyed
    /// by bundle identifier, since `save` renders the card before an `AppshotRecord`
    /// exists. Returns nil on any failure.
    func appIconCGImage(forBundleID bundleID: String) -> CGImage? {
        appIconBitmap(forBundleID: bundleID)?.cgImage
    }

    /// Loads the app's icon (sized to 128x128) as a bitmap, keyed by bundle
    /// identifier. Shared by `appIconDataURL(for:)` and `appIconCGImage(forBundleID:)`.
    private func appIconBitmap(forBundleID bundleID: String) -> NSBitmapImageRep? {
        guard bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 128, height: 128)
        guard let tiffData = icon.tiffRepresentation else {
            return nil
        }
        return NSBitmapImageRep(data: tiffData)
    }

    func dayFolderName(for date: Date) -> String {
        posixFormatter(dateFormat: "yyyy-MM-dd").string(from: date)
    }

    func timestampFolderName(for date: Date) -> String {
        posixFormatter(dateFormat: "HHmmss").string(from: date)
    }

    private func posixFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = dateFormat
        return formatter
    }
}
