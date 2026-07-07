import AppKit
import AppshotsCore
import ApplicationServices
import CoreGraphics
import Foundation

/// Long-lived headless host for the global capture hot key.
///
/// The capture engine itself is already headless (the `capture` command and the
/// `mcp` server prove it). The daemon exists for one reason: `NSEvent` global
/// monitors — the mechanism `AppshotsHotKeyMonitor` uses to observe the trigger
/// keys system-wide — require a running AppKit run loop. This brings one up
/// without any menu-bar UI, matching the GUI app's `LSUIElement`/`.accessory`
/// activation so it stays out of the Dock.
///
/// Ownership is keyed on ``AppshotSettings/startupMode``: the daemon owns the hot
/// key **only** in `.headless` mode, where the GUI never arms its own monitor.
/// In `.gui`/`.none` the GUI owns it, so a stale LaunchAgent that wakes up in
/// those modes exits immediately, and a running daemon yields the moment the mode
/// changes away from `.headless` (observed via the settings notification). The
/// GUI being open does **not** make the daemon yield — in headless mode the GUI
/// stays unarmed, so the daemon must keep hosting the hot key. A second daemon is
/// prevented by the advisory ``HotKeyLock``; NSEvent global monitors are
/// per-process and observe-only, so two armed monitors would double-fire the chord.
///
/// The `NSApplication.shared` host and `NSApp.run()` live here in the executable
/// on purpose — `AppshotsCore` stays UI/run-loop free.
@MainActor
enum AppshotDaemon {
    /// Retained for the process lifetime so the advisory hot-key lock stays held.
    private static let hotKeyLock = HotKeyLock(rootURL: settingsStore.rootURL)
    private static var monitor: AppshotsHotKeyMonitor?
    /// Retained for the process lifetime so settings change delivery keeps working.
    private static var settingsToken: AppshotSettingsObservationToken?
    /// Retained so the GCD signal sources are not cancelled by deinit.
    private static var signalSources: [DispatchSourceSignal] = []
    private static let settingsStore = AppshotSettingsStore()
    private static var copyOnCapture = false
    private static var postCaptureSendTarget: String?

    /// Brings up the headless run loop and blocks on it. Returns only via the
    /// signal handlers (which call `exit`), or an early clean exit when the
    /// startup mode is not headless or another daemon already owns the hot key.
    static func run() {
        let settings = settingsStore.load()

        // Ownership guard: the daemon owns the hot key only in headless mode. In
        // `.gui`/`.none` the GUI owns it, so a leftover LaunchAgent must yield.
        guard settings.startupMode == .headless else {
            AppLog.lifecycle.notice("daemon not starting: startupMode=\(settings.startupMode.rawValue, privacy: .public) (the GUI owns the hot key)")
            writeStderr("Appshots startup mode is not headless; the GUI owns the hot key.")
            Foundation.exit(0)
        }

        // Only one daemon may arm a monitor — NSEvent global monitors are
        // per-process and observe-only, so a second armed monitor would
        // double-fire the chord.
        guard hotKeyLock.tryAcquire() else {
            AppLog.lifecycle.notice("daemon not starting: hot-key lock already held by another daemon")
            writeStderr("another appshots daemon is already running.")
            Foundation.exit(0)
        }

        let app = NSApplication.shared
        // Dock-less, matching the LSUIElement menu-bar app. Never .regular
        // (would show a Dock icon) or .prohibited (would block event monitors).
        app.setActivationPolicy(.accessory)

        checkPermissions()

        copyOnCapture = settings.copyOnCapture
        postCaptureSendTarget = settings.postCaptureSendTarget
        let triggerKey = triggerKeySet(from: settings)

        let monitor = AppshotsHotKeyMonitor(triggerKey: triggerKey) {
            performCapture()
        }
        Self.monitor = monitor

        // Warm capture dependencies so the first hot-key capture is as fast as
        // subsequent ones.
        AppshotCaptureService.prewarm()

        // Live-reload: a CLI or GUI trigger-key / copy-on-capture change updates
        // the running daemon without a restart; a startup-mode change yields.
        settingsToken = AppshotSettingsStore.observe {
            Task { @MainActor in reloadSettings() }
        }

        installSignalHandlers()

        monitor.start()
        AppLog.lifecycle.notice("daemon started; hosting headless hot-key run loop trigger=\(Array(triggerKey).sorted().map(String.init).joined(separator: ","), privacy: .public)")
        app.run()
    }

    // MARK: - Capture

    private static func performCapture() {
        do {
            let record = try AppshotCaptureService.captureFrontmostApplication()
            // The send flow ends by restoring the standard clipboard copy, so a
            // configured target implies the copy even when copyOnCapture is off.
            let copied = copyOnCapture || postCaptureSendTarget != nil
            if copied {
                PasteboardWriter.copyAppshotMarkup(for: record)
            }
            if let target = postCaptureSendTarget {
                Task { @MainActor in await PostCaptureSender.send(record: record, toBundleID: target) }
            }
            AppLog.lifecycle.notice("daemon capture saved id=\(record.id, privacy: .public) copied=\(copied, privacy: .public)")
        } catch {
            AppLog.capture.error("daemon capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Settings

    private static func triggerKeySet(from settings: AppshotSettings) -> Set<CGKeyCode> {
        // CGKeyCode is a typealias for UInt16, so the stored raw codes map directly.
        Set(settings.triggerKey)
    }

    private static func reloadSettings() {
        let settings = settingsStore.load()

        // The daemon owns the hot key only in headless mode. If the mode changed
        // (e.g. `startup enable --gui` or `config set startupMode none`), yield so
        // the daemon does not keep firing captures after the user switched modes.
        guard settings.startupMode == .headless else {
            AppLog.lifecycle.notice("daemon yielding: startupMode changed to \(settings.startupMode.rawValue, privacy: .public)")
            shutdown()
            return
        }

        copyOnCapture = settings.copyOnCapture
        postCaptureSendTarget = settings.postCaptureSendTarget
        let triggerKey = triggerKeySet(from: settings)
        monitor?.updateTriggerKey(triggerKey)
        AppLog.lifecycle.notice("daemon settings reloaded trigger=\(Array(triggerKey).sorted().map(String.init).joined(separator: ","), privacy: .public) copied=\(copyOnCapture, privacy: .public)")
    }

    // MARK: - Permissions

    private static func checkPermissions() {
        // Surface the Accessibility prompt if not yet trusted. The option key is
        // referenced by its literal value because the imported global
        // `kAXTrustedCheckOptionPrompt` is not concurrency-safe under Swift 6.
        let axOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let axTrusted = AXIsProcessTrustedWithOptions(axOptions)

        var screenGranted = CGPreflightScreenCaptureAccess()
        if screenGranted == false {
            // Surfaces the Screen Recording prompt; the grant takes effect on relaunch.
            screenGranted = CGRequestScreenCaptureAccess()
        }

        AppLog.permissions.notice("daemon permissions accessibility=\(axTrusted, privacy: .public) screenRecording=\(screenGranted, privacy: .public)")
        if axTrusted == false {
            AppLog.permissions.warning("daemon: Accessibility not granted — the hot key won't fire until it is granted in System Settings > Privacy & Security > Accessibility")
            writeStderr("Accessibility is not granted; the hot key will not fire until it is granted in System Settings > Privacy & Security > Accessibility. The daemon will keep running so the grant can take effect.")
        }
    }

    // MARK: - Signal handling

    private static func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            // Ignore the default disposition so the dispatch source is the only handler.
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    AppLog.lifecycle.notice("daemon received signal \(sig, privacy: .public); shutting down")
                    shutdown()
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private static func shutdown() {
        monitor?.stop()
        settingsToken?.cancel()
        hotKeyLock.release()
        Foundation.exit(0)
    }

    // MARK: - Helpers

    private static func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
