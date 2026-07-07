import AppKit

/// Sends the just-captured appshot to another app ("send to Claude Desktop"):
/// activates the target — launching it when needed — waits for it to become
/// frontmost, and synthesizes Cmd+V so the appshot lands in its composer.
///
/// The general pasteboard must already hold the appshot (markup + screenshot);
/// the capture paths copy before calling this. Posting the keystroke rides the
/// Accessibility grant that capture already requires. Best-effort by design: a
/// target that cannot be activated logs and gives up — a capture never fails
/// on the send step.
@MainActor
public enum PostCaptureSender {
    /// Claude Desktop's bundle identifier, the primary target this exists for.
    public static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    public static func send(toBundleID bundleID: String) async {
        guard await activate(bundleID: bundleID) else {
            AppLog.capture.error("post-capture send: could not activate \(bundleID, privacy: .public)")
            return
        }
        // Give the freshly activated app a beat to focus its composer.
        try? await Task.sleep(for: .milliseconds(350))
        postCommandV()
        AppLog.capture.notice("post-capture send: pasted into \(bundleID, privacy: .public)")
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
