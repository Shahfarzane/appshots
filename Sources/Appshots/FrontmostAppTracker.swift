import AppKit
import AppshotsCore

@MainActor
final class FrontmostAppTracker {
    private var observer: NSObjectProtocol?
    private(set) var lastNonSelfApp: NSRunningApplication?

    func start() {
        updateIfUsable(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.updateIfUsable(app)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    func captureTarget() -> FrontmostAppTarget? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let app = usableApp(frontmost) ?? usableApp(lastNonSelfApp)
        guard let app else { return nil }

        return FrontmostAppTarget(
            name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
            bundleID: app.bundleIdentifier ?? "",
            pid: app.processIdentifier
        )
    }

    private func updateIfUsable(_ app: NSRunningApplication?) {
        guard let app = usableApp(app) else { return }
        let changedApp = app.processIdentifier != lastNonSelfApp?.processIdentifier
        lastNonSelfApp = app
        // Warm the new frontmost app's accessibility tree in the background so the first capture of
        // it is as fast as subsequent ones (the one-time AX connection + enhanced-UI rebuild cost).
        if changedApp {
            AppshotCaptureService.prewarm(pid: app.processIdentifier)
        }
    }

    private func usableApp(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy != .prohibited,
              app.localizedName?.isEmpty == false || app.bundleIdentifier?.isEmpty == false
        else {
            return nil
        }
        return app
    }
}
