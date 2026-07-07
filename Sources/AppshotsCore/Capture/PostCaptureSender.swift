import AppKit

/// Sends the just-captured appshot to another app ("send to Claude Desktop"):
/// activates the target — launching it when needed — waits for it to become
/// frontmost, and pastes the capture into its composer via synthesized Cmd+V.
///
/// The paste is deliberately **not** the full `<appshot>` markup (a wall of
/// AX-tree text in a chat input): it is two quick pastes — the screenshot as
/// an image, then one short reference line naming the capture id and its
/// `appshot.md` path — so the composer shows a thumbnail plus one line, and an
/// agent pulls the full context via the appshots MCP server or the file path
/// only when it needs it. The general pasteboard is restored to the standard
/// full-markup copy afterwards.
///
/// Posting the keystrokes rides the Accessibility grant that capture already
/// requires. Best-effort by design: a target that cannot be activated logs and
/// gives up — a capture never fails on the send step.
@MainActor
public enum PostCaptureSender {
    /// Claude Desktop's bundle identifier, the primary target this exists for.
    public static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    /// Serialises overlapping sends: a rapid second capture waits for the
    /// first paste sequence to finish instead of interleaving pasteboard
    /// writes and keystrokes with it.
    private static var lastSend: Task<Void, Never>?

    /// - Parameter image: an already-decoded screenshot to reuse; falls back to
    ///   reading `record.screenshotURL` from disk when nil.
    public static func send(record: AppshotRecord, image: NSImage? = nil, toBundleID bundleID: String) async {
        let previous = lastSend
        let task = Task {
            await previous?.value
            await performSend(record: record, image: image, toBundleID: bundleID)
        }
        lastSend = task
        await task.value
    }

    private static func performSend(record: AppshotRecord, image: NSImage?, toBundleID bundleID: String) async {
        guard await activate(bundleID: bundleID) else {
            AppLog.capture.error("post-capture send: could not activate \(bundleID, privacy: .public)")
            return
        }
        // Give the freshly activated app a beat to focus its composer.
        try? await Task.sleep(for: .milliseconds(350))

        let pasteboard = NSPasteboard.general
        let screenshot = image ?? record.screenshotURL.flatMap { NSImage(contentsOf: $0) }

        if let screenshot {
            pasteboard.clearContents()
            pasteboard.writeObjects([screenshot])
            postCommandV()
            // Let the composer ingest the image before the second paste.
            try? await Task.sleep(for: .milliseconds(300))
        }

        pasteboard.clearContents()
        pasteboard.setString(referenceLine(for: record), forType: .string)
        postCommandV()
        try? await Task.sleep(for: .milliseconds(150))

        // Leave the clipboard as the documented capture copy (full markup +
        // screenshot), not the transient send payload.
        PasteboardWriter.copyAppshotMarkup(for: record, image: screenshot)
        AppLog.capture.notice("post-capture send: pasted appshot \(record.id, privacy: .public) into \(bundleID, privacy: .public)")
    }

    /// The one-line composer reference: the capture id (resolvable through the
    /// appshots MCP tools) plus the on-disk prompt path for direct reads.
    static func referenceLine(for record: AppshotRecord) -> String {
        "Attached appshot \(record.id). Full context: \(record.appshotTextPath)"
    }

    /// Activates (or launches) the target and waits until it is frontmost.
    private static func activate(bundleID: String) async -> Bool {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.activate()
            return await waitUntilFrontmost(bundleID: bundleID, timeout: .seconds(3))
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        guard (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil else {
            return false
        }
        // Cold launch: allow longer for the first window to appear.
        return await waitUntilFrontmost(bundleID: bundleID, timeout: .seconds(10))
    }

    private static func waitUntilFrontmost(bundleID: String, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // 9 = kVK_ANSI_V.
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
