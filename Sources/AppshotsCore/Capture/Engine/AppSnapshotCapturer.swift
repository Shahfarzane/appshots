import Foundation

/// Product-facing facade for capturing macOS app state (accessibility tree +
/// screenshot).
///
/// Keep one client alive for a capture and call `finish()` when done.
public final class AppSnapshotCapturer: @unchecked Sendable {
    /// Screenshot compression policy used by state and post-action captures.
    public var screenshotCompression: ScreenshotCompression

    public init(
        screenshotCompression: ScreenshotCompression = .foregroundDefault
    ) {
        self.screenshotCompression = screenshotCompression
    }

    deinit {
        finish()
    }

    /// Marks the capture session finished.
    public func finish() {}

    /// Captures a single snapshot and returns both the formatted output and the
    /// structured state, avoiding a second accessibility-tree walk when a caller
    /// needs both (e.g. appshot capture).
    public func appStateWithStructured(
        app appIdentifier: String,
        windowTitle: String? = nil,
        windowID: Int? = nil,
        includeScreenshot: Bool = false,
        options: CaptureOptions = .default,
        eventSink: CaptureEventSink? = nil
    ) throws -> (output: CaptureOutput, state: CapturedAppState) {
        AppLog.capture.debug("appStateWithStructured app=\(appIdentifier, privacy: .public) screenshot=\(includeScreenshot, privacy: .public)")
        return try SnapshotCapture.getAppStateAndStructured(
            appIdentifier: appIdentifier,
            windowTitle: windowTitle,
            windowID: windowID,
            includeScreenshot: includeScreenshot,
            screenshotCompression: screenshotCompression,
            options: options,
            eventSink: eventSink
        )
    }
}

public enum SnapshotCapture {
    /// Captures a single snapshot of the target and returns both the formatted
    /// output and the structured state. Use this when a caller needs both
    /// representations (e.g. an appshot capture) so the accessibility tree is
    /// walked once instead of twice.
    public static func getAppStateAndStructured(
        appIdentifier: String,
        windowTitle: String?,
        windowID: Int?,
        includeScreenshot: Bool,
        screenshotCompression: ScreenshotCompression = .foregroundDefault,
        options: CaptureOptions = .default,
        eventSink: CaptureEventSink? = nil
    ) throws -> (output: CaptureOutput, state: CapturedAppState) {
        let result = try captureSnapshotAfterPreparingTarget(
            appIdentifier: appIdentifier,
            windowTitle: windowTitle,
            windowID: windowID,
            includeScreenshot: includeScreenshot,
            screenshotCompression: screenshotCompression,
            options: options,
            eventSink: eventSink
        )
        return try AccessibilityCaptureEngine.persistFormatAndBuildState(
            snapshot: result.snapshot,
            options: options
        )
    }
}

extension SnapshotCapture {
    static func captureSnapshotWithWindowFallback(
        appIdentifier: String,
        windowTitle: String?,
        windowID: Int?,
        includeScreenshot: Bool,
        screenshotCompression: ScreenshotCompression,
        filterVisibleNodes: Bool = true,
        eventSink: CaptureEventSink? = nil
    ) throws -> (snapshot: RuntimeAppSnapshot, usedWindowFallback: Bool) {
        do {
            let snapshot = try AccessibilityCaptureEngine.captureSnapshot(
                appIdentifier: appIdentifier,
                selection: WindowSelection(titleSubstring: windowTitle, windowID: windowID),
                includeScreenshot: includeScreenshot,
                screenshotCompression: screenshotCompression,
                filterVisibleNodes: filterVisibleNodes,
                eventSink: eventSink
            )
            return (snapshot, false)
        } catch let error as CaptureError {
            guard case .windowNotFound = error,
                  windowID == nil,
                  let windowTitle,
                  windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else {
                throw error
            }

            let snapshot = try AccessibilityCaptureEngine.captureSnapshot(
                appIdentifier: appIdentifier,
                includeScreenshot: includeScreenshot,
                screenshotCompression: screenshotCompression,
                filterVisibleNodes: filterVisibleNodes,
                eventSink: eventSink
            )
            return (snapshot, true)
        }
    }

    static func captureSnapshotAfterPreparingTarget(
        appIdentifier: String,
        windowTitle: String?,
        windowID: Int?,
        includeScreenshot: Bool,
        screenshotCompression: ScreenshotCompression,
        options: CaptureOptions = .default,
        eventSink: CaptureEventSink? = nil
    ) throws -> (snapshot: RuntimeAppSnapshot, usedWindowFallback: Bool) {
        try captureSnapshotWithWindowFallback(
            appIdentifier: appIdentifier,
            windowTitle: windowTitle,
            windowID: windowID,
            includeScreenshot: includeScreenshot,
            screenshotCompression: screenshotCompression,
            filterVisibleNodes: options.filterVisibleNodes,
            eventSink: eventSink
        )
    }
}
