import AppKit
import Foundation

/// Writes an appshot capture's markup (and screenshot, when present) to the
/// general pasteboard. Stateless helper extracted from `AppshotsModel`.
public enum PasteboardWriter {
    /// - Parameter image: an already-decoded screenshot to reuse, avoiding a second file read +
    ///   decode of the full-resolution PNG. Falls back to reading from disk when nil.
    public static func copyAppshotMarkup(for record: AppshotRecord, image: NSImage? = nil) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let image = image ?? record.screenshotURL.flatMap({ NSImage(contentsOf: $0) }) {
            pasteboard.writeObjects([image])
        }

        pasteboard.setString(clipboardText(for: record), forType: .string)
    }

    private static func clipboardText(for record: AppshotRecord) -> String {
        if let prompt = try? String(contentsOf: record.appshotTextURL, encoding: .utf8) {
            return prompt
        }
        return record.referenceText
    }
}
