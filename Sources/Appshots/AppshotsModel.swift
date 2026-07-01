import AppKit
import ApplicationServices
import AppshotsCore
import Foundation
import Observation

@MainActor
@Observable
final class AppshotsModel {
    var recentCaptures: [AppshotRecord] = []
    var pendingCapture: PendingCaptureViewState?
    var historyVersion: Int = 0
    var statusMessage = "Ready"
    var isCapturing = false
    var hasAccessibilityPermission = false
    var hasScreenRecordingPermission = false
    var permissionRequestState: AppshotCaptureStatus?
    var triggerKey: Set<CGKeyCode> {
        didSet {
            guard oldValue != triggerKey else { return }
            if isApplyingExternalSettings == false {
                persistTriggerKey(triggerKey)
            }
            statusMessage = "Trigger key updated"
            onTriggerKeyChange?(triggerKey)
        }
    }
    var playsCaptureSound: Bool {
        didSet {
            guard oldValue != playsCaptureSound else { return }
            if isApplyingExternalSettings == false {
                AppshotSoundPlayer.setEnabled(playsCaptureSound)
            }
        }
    }
    /// Whether the app shows a Dock icon. Persisted to `config.json` and applied
    /// live by flipping `NSApp` between `.regular` (Dock) and `.accessory`
    /// (menu-bar-only). A CLI write live-reloads through `applyExternalSettingsChange`.
    var showInDock: Bool {
        didSet {
            guard oldValue != showInDock else { return }
            if isApplyingExternalSettings == false {
                persistShowInDock(showInDock)
            }
            applyDockVisibility()
        }
    }

    /// Bumped whenever the GUI login-item status should be re-read. Reading it
    /// inside the `launchAtLogin` / `loginItemRequiresApproval` getters
    /// establishes the SwiftUI observation dependency so the UI refreshes when
    /// status changes out of band (e.g. the user toggled it in System Settings).
    private var startupStatusToken = 0

    /// Whether the GUI app launches at login. Source of truth is the live
    /// `SMAppService` status (never cached); the setter also writes
    /// `startupMode` to `config.json` and enforces mutual exclusion with the
    /// headless daemon LaunchAgent.
    var launchAtLogin: Bool {
        get {
            _ = startupStatusToken
            return loginItem.isEnabled
        }
        set {
            if newValue {
                setStartupMode(.gui)
                registerLoginItem()
                uninstallHeadlessAgent()
            } else {
                setStartupMode(.none)
                unregisterLoginItem()
            }
            refreshStartupStatus()
        }
    }

    /// Whether the GUI login item is awaiting the user's approval in System
    /// Settings > Login Items.
    var loginItemRequiresApproval: Bool {
        _ = startupStatusToken
        return loginItem.requiresApproval
    }

    @ObservationIgnored weak var frontmostTracker: FrontmostAppTracker?
    @ObservationIgnored var playCaptureAnimation: ((AppshotRecord, NSImage?) -> Void)?
    @ObservationIgnored var playPendingCaptureAnimation: ((CGRect, NSImage, String, String) -> Void)?
    @ObservationIgnored var showPermissionPanel: (() -> Void)?
    @ObservationIgnored var openSettings: (() -> Void)?
    @ObservationIgnored var openPreview: ((AppshotRecord) -> Void)?
    @ObservationIgnored var onTriggerKeyChange: ((Set<CGKeyCode>) -> Void)?
    /// Pauses/resumes the global hot-key monitor (e.g. while recording a new
    /// trigger key in settings). `true` = active, `false` = paused. Does **not**
    /// touch the cross-process hot-key lock — the GUI keeps ownership while paused.
    @ObservationIgnored var setHotKeyMonitorActive: ((Bool) -> Void)?

    /// Arms or yields the GUI's ownership of the global hot key for the current
    /// `startupMode`: `true` acquires the cross-process ``HotKeyLock`` and starts
    /// the monitor; `false` stops the monitor and releases the lock so the
    /// headless daemon can take over. Distinct from ``setHotKeyMonitorActive``,
    /// which only pauses/resumes the monitor without surrendering ownership.
    @ObservationIgnored var setHotKeyOwnership: ((Bool) -> Void)?

    private let store = AppshotStore()
    private let settingsStore = AppshotSettingsStore()
    private let loginItem = LoginItemController()
    private let launchAgent = LaunchAgentController()
    private let maxRecentCaptures = 10
    private var animatedPendingRequestIDs = Set<String>()
    private var pendingAnimationStarted = false
    /// Set while applying a settings change that arrived from another process, so
    /// the `triggerKey` / `playsCaptureSound` `didSet` handlers don't re-persist
    /// (and re-broadcast) what we just loaded.
    @ObservationIgnored private var isApplyingExternalSettings = false
    @ObservationIgnored private var settingsObservationToken: AppshotSettingsObservationToken?

    init() {
        // Seed config.json from legacy UserDefaults on first run, then make it the
        // source of truth for the trigger key and capture sound.
        AppshotSettingsMigration.seedIfNeeded(store: settingsStore)
        let settings = settingsStore.load()
        triggerKey = Self.triggerKey(from: settings)
        playsCaptureSound = AppshotSoundPlayer.isEnabled
        showInDock = settings.showInDock
        observeSettingsChanges()
    }

    /// Persists the Dock-visibility preference to `config.json`.
    private func persistShowInDock(_ showInDock: Bool) {
        do {
            try settingsStore.mutate { $0.showInDock = showInDock }
        } catch {
            AppLog.store.error("failed to persist showInDock: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Applies the current Dock-visibility preference by switching the app's
    /// activation policy. `.regular` shows a Dock icon; `.accessory` is
    /// menu-bar-only. Safe to call repeatedly.
    func applyDockVisibility() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    /// Reads the trigger key from a settings snapshot, mapping the persisted raw
    /// key codes back to `CGKeyCode`.
    private static func triggerKey(from settings: AppshotSettings) -> Set<CGKeyCode> {
        Set(settings.triggerKey.map { CGKeyCode($0) })
    }

    private func persistTriggerKey(_ triggerKey: Set<CGKeyCode>) {
        let codes = triggerKey.sorted().map { UInt16($0) }
        do {
            try settingsStore.mutate { $0.triggerKey = codes }
        } catch {
            AppLog.store.error("failed to persist trigger key: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Registers a cross-process observer so a CLI write to `config.json`
    /// live-updates the running app (trigger key + capture sound) without relaunch.
    private func observeSettingsChanges() {
        settingsObservationToken = AppshotSettingsStore.observe { [weak self] in
            Task { @MainActor in
                self?.applyExternalSettingsChange()
            }
        }
    }

    /// Reloads settings written by another process and applies them, guarding the
    /// `didSet` persistence so we don't echo the change back to disk.
    private func applyExternalSettingsChange() {
        let settings = settingsStore.load()
        let reloadedTriggerKey = Self.triggerKey(from: settings)

        isApplyingExternalSettings = true
        defer { isApplyingExternalSettings = false }

        if triggerKey != reloadedTriggerKey {
            triggerKey = reloadedTriggerKey
        }
        if playsCaptureSound != settings.captureSound {
            playsCaptureSound = settings.captureSound
        }
        if showInDock != settings.showInDock {
            // `didSet` re-applies the activation policy live; the guard above
            // suppresses the redundant persist back to disk.
            showInDock = settings.showInDock
        }

        // A CLI `startup --gui/--headless` write reconciles the running app live.
        reconcileStartupMode()
    }

    // MARK: - Launch at login

    /// Re-reads the live login-item status, refreshing any bound UI. Cheap to
    /// call on settings-window appear and `NSApplication.didBecomeActive`.
    func refreshStartupStatus() {
        startupStatusToken &+= 1
    }

    /// Whether the GUI app owns the global hot key for the current `startupMode`.
    /// The GUI owns it in `.gui`/`.none`; in `.headless` the daemon owns it.
    var shouldGUIOwnHotKey: Bool {
        settingsStore.load().startupMode != .headless
    }

    /// Reconciles the GUI login item *and* hot-key ownership against
    /// `startupMode` in `config.json`:
    /// `.gui` registers the login item (and removes any headless agent) and arms
    /// the hot key; `.none` unregisters the login item but still owns the hot key
    /// while running; `.headless` unregisters the login item and yields the hot
    /// key (stops the monitor + releases the lock) to the daemon. The GUI never
    /// installs the headless LaunchAgent — that is the CLI's job.
    func reconcileStartupMode() {
        switch settingsStore.load().startupMode {
        case .gui:
            registerLoginItem()
            uninstallHeadlessAgent()
            setHotKeyOwnership?(true)
        case .headless:
            unregisterLoginItem()
            setHotKeyOwnership?(false)
        case .none:
            unregisterLoginItem()
            setHotKeyOwnership?(true)
        }
        refreshStartupStatus()
    }

    /// Opens System Settings > Login Items so the user can approve the login item.
    func openLoginItemsSettings() {
        SystemSettings.open(.loginItems)
    }

    private func setStartupMode(_ mode: StartupMode) {
        do {
            try settingsStore.mutate { $0.startupMode = mode }
        } catch {
            AppLog.startup.error("failed to persist startupMode: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func registerLoginItem() {
        do {
            try loginItem.register()
        } catch {
            AppLog.startup.error("login item register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func unregisterLoginItem() {
        do {
            try loginItem.unregister()
        } catch {
            AppLog.startup.error("login item unregister failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the headless daemon LaunchAgent if it is installed (mutual
    /// exclusion: the GUI login item and the daemon must not both run).
    private func uninstallHeadlessAgent() {
        guard launchAgent.isInstalled() else { return }
        do {
            try launchAgent.uninstall()
        } catch {
            AppLog.startup.error("headless agent uninstall failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startSession() {
        do {
            try store.ensureRootDirectory()
            AppshotCaptureService.prewarm()
            recentCaptures = store.recentCaptures(limit: maxRecentCaptures)
            statusMessage = "Ready"
            AppLog.lifecycle.notice("session started recent=\(self.recentCaptures.count, privacy: .public)")
        } catch {
            recentCaptures = []
            statusMessage = error.localizedDescription
            AppLog.lifecycle.error("session start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func endSession() {
        recentCaptures = []
    }

    func refreshPermissions() {
        let previousAX = hasAccessibilityPermission
        let previousScreen = hasScreenRecordingPermission
        hasAccessibilityPermission = AXIsProcessTrusted()
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        if hasAccessibilityPermission != previousAX || hasScreenRecordingPermission != previousScreen {
            AppLog.permissions.notice("permissions accessibility=\(self.hasAccessibilityPermission, privacy: .public) screenRecording=\(self.hasScreenRecordingPermission, privacy: .public)")
        }
        if hasAccessibilityPermission, hasScreenRecordingPermission {
            permissionRequestState = nil
        }
    }

    func requestAccessibilityPermission() {
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
    }

    func requestScreenRecordingPermission() {
        hasScreenRecordingPermission = CGRequestScreenCaptureAccess()
    }

    func captureFrontmostApp() {
        guard isCapturing == false else { return }

        refreshPermissions()
        guard hasAccessibilityPermission, hasScreenRecordingPermission else {
            permissionRequestState = .permissionsPending
            statusMessage = "Grant Accessibility and Screen Recording to capture appshots"
            AppLog.permissions.warning("capture blocked: missing permissions accessibility=\(self.hasAccessibilityPermission, privacy: .public) screenRecording=\(self.hasScreenRecordingPermission, privacy: .public)")
            showPermissionPanel?()
            NSApp.requestUserAttention(.informationalRequest)
            return
        }

        guard let target = frontmostTracker?.captureTarget() else {
            statusMessage = "No frontmost app to capture"
            AppLog.capture.warning("capture skipped: no frontmost app to capture")
            return
        }

        isCapturing = true
        pendingAnimationStarted = false
        pendingCapture = PendingCaptureViewState(
            requestID: "pending",
            appName: target.name,
            windowTitle: "Resolving window...",
            screenshotURL: nil,
            windowFrame: nil
        )
        statusMessage = "Capturing \(target.name)..."
        AppLog.capture.notice("capture requested app=\(target.name, privacy: .public) bundle=\(target.bundleID, privacy: .public)")

        Task.detached(priority: .userInitiated) {
            do {
                let record = try AppshotCaptureService.captureWithEventHandler(target: target) { event in
                    Task { @MainActor in
                        self.applyCaptureEvent(event, target: target)
                    }
                }
                // Decode the screenshot once, off the main thread, so the animation and the
                // clipboard write don't each re-read and re-decode the full-resolution PNG.
                let screenshotImage = record.screenshotURL.flatMap { NSImage(contentsOf: $0) }
                await MainActor.run {
                    // Visible feedback first: list update + flight animation, nothing heavy.
                    let insertStart = Date()
                    self.insertRecentCapture(record)
                    try? self.store.appendMetricPhase(
                        for: record,
                        name: "UI insert",
                        durationMs: Date().timeIntervalSince(insertStart) * 1000
                    )
                    self.permissionRequestState = nil
                    self.isCapturing = false
                    self.pendingCapture = nil
                    self.statusMessage = "Captured \(record.appName) and copied appshot"
                    if self.pendingAnimationStarted == false {
                        try? self.store.appendMetricPhase(for: record, name: "animation start")
                        self.playCaptureAnimation?(record, screenshotImage)
                    } else {
                        try? self.store.appendMetricPhase(
                            for: record,
                            name: "animation start",
                            detail: "from_screenshot_event"
                        )
                    }
                }
                // After the first frame ships: the clipboard write (which forces a TIFF encode)
                // and the permission refresh are off the visible critical path.
                await MainActor.run {
                    let pasteboardStart = Date()
                    PasteboardWriter.copyAppshotMarkup(for: record, image: screenshotImage)
                    try? self.store.appendMetricPhase(
                        for: record,
                        name: "clipboard write",
                        durationMs: Date().timeIntervalSince(pasteboardStart) * 1000
                    )
                    self.refreshPermissions()
                    NSApp.requestUserAttention(.informationalRequest)
                }
            } catch {
                AppLog.capture.error("capture failed app=\(target.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.isCapturing = false
                    self.pendingCapture = nil
                    self.pendingAnimationStarted = false
                    self.statusMessage = error.localizedDescription
                    self.refreshPermissions()
                }
            }
        }
    }

    private func applyCaptureEvent(_ event: AppshotCaptureEvent, target: FrontmostAppTarget) {
        switch event.status {
        case .started:
            statusMessage = "Capturing \(target.name)..."
        case .permissionsPending:
            permissionRequestState = .permissionsPending
            statusMessage = "Waiting for permissions: \(event.permissionGrantState ?? "unknown")"
        case .metadata:
            pendingCapture = PendingCaptureViewState(
                requestID: event.requestID,
                appName: target.name,
                windowTitle: event.windowTitle ?? "Untitled window",
                screenshotURL: pendingCapture?.screenshotURL,
                windowFrame: event.windowFrame
            )
            statusMessage = "Captured window metadata"
        case .axText:
            statusMessage = "Captured app text"
        case .screenshot:
            if let screenshotPath = event.screenshotPath {
                let screenshotURL = URL(fileURLWithPath: screenshotPath)
                pendingCapture = PendingCaptureViewState(
                    requestID: event.requestID,
                    appName: pendingCapture?.appName ?? target.name,
                    windowTitle: pendingCapture?.windowTitle ?? "Untitled window",
                    screenshotURL: screenshotURL,
                    windowFrame: pendingCapture?.windowFrame
                )
                if animatedPendingRequestIDs.contains(event.requestID) == false,
                   let frame = pendingCapture?.windowFrame,
                   let image = NSImage(contentsOf: screenshotURL) {
                    animatedPendingRequestIDs.insert(event.requestID)
                    pendingAnimationStarted = true
                    playPendingCaptureAnimation?(frame, image, target.name, target.bundleID)
                }
            }
            statusMessage = "Captured screenshot"
        case .completed:
            permissionRequestState = nil
            pendingCapture = nil
            animatedPendingRequestIDs.remove(event.requestID)
            if let appName = event.record?.appName {
                statusMessage = "Captured \(appName)"
            }
        case .failed:
            pendingCapture = nil
            pendingAnimationStarted = false
            statusMessage = event.failureReason ?? "Capture failed"
        case .permissionsAbandoned:
            permissionRequestState = .permissionsAbandoned
            statusMessage = "Permission request abandoned"
        case .discarded:
            statusMessage = "Capture discarded"
        }
    }

    func allCaptures() -> [AppshotRecord] {
        store.allCaptures()
    }

    func deleteSelected(_ ids: Set<String>) {
        guard ids.isEmpty == false else { return }

        let store = store
        let identifiers = Array(ids)
        let limit = maxRecentCaptures
        Task.detached(priority: .userInitiated) {
            do {
                let deleted = try store.deleteCaptures(ids: identifiers)
                let captures = store.recentCaptures(limit: limit)
                await MainActor.run {
                    self.recentCaptures = captures
                    self.historyVersion += 1
                    self.statusMessage = "Deleted \(deleted) appshot\(deleted == 1 ? "" : "s")"
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func clearAllHistory() {
        let store = store
        Task.detached(priority: .userInitiated) {
            do {
                try store.clearAll()
                await MainActor.run {
                    self.recentCaptures = []
                    self.historyVersion += 1
                    self.statusMessage = "Cleared appshot history"
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func copyAppshotMarkup(for record: AppshotRecord) {
        PasteboardWriter.copyAppshotMarkup(for: record)
        statusMessage = "Copied appshot"
    }

    private func insertRecentCapture(_ record: AppshotRecord) {
        recentCaptures.removeAll { $0.id == record.id }
        recentCaptures.insert(record, at: 0)

        recentCaptures = Array(recentCaptures.prefix(maxRecentCaptures))
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

struct PendingCaptureViewState: Identifiable, Equatable {
    var requestID: String
    var appName: String
    var windowTitle: String
    var screenshotURL: URL?
    var windowFrame: CGRect?

    var id: String { requestID }
}
