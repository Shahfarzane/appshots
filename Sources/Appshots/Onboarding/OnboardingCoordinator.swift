import AppKit
import ApplicationServices
import AppshotsCore
import Foundation

/// Drives the sequential permission onboarding on top of the vendored
/// `PermissionFlow` floating panel.
///
/// The coordinator walks a strictly ordered list of permission gates
/// (Accessibility first, then Screen Recording). For each ungranted gate it
/// opens System Settings plus the floating drag panel, then polls the live
/// system grant at a low cadence — only while a gate is active — until the
/// permission is granted. Live system checks are the source of truth;
/// persistence merely prevents re-nagging once everything is in place.
@MainActor
final class OnboardingCoordinator {
    /// A single permission step in the onboarding flow.
    private enum Gate {
        case accessibility
        case screenRecording

        /// The matching pane used to drive the floating PermissionFlow panel.
        var pane: PermissionFlowPane {
            switch self {
            case .accessibility: .accessibility
            case .screenRecording: .screenRecording
            }
        }

        /// Whether the capture stack needs a fresh process after this grant.
        ///
        /// Accessibility takes effect live, while Screen Recording only becomes
        /// usable after the app is relaunched into a new process.
        var requiresRelaunchAfterGrant: Bool {
            switch self {
            case .accessibility: false
            case .screenRecording: true
            }
        }

        /// The live, authoritative grant check for this gate.
        var isGranted: Bool {
            switch self {
            case .accessibility: AXIsProcessTrusted()
            case .screenRecording: CGPreflightScreenCaptureAccess()
            }
        }
    }

    private static let pollInterval: TimeInterval = 0.5

    /// Strict order: Accessibility must be granted before Screen Recording.
    private let gates: [Gate] = [.accessibility, .screenRecording]

    private let controller: PermissionFlowController
    private let settingsStore: AppshotSettingsStore

    private var activeGateIndex: Int?
    private var pollTimer: Timer?
    private var didBecomeActiveObserver: NSObjectProtocol?

    init(settingsStore: AppshotSettingsStore = AppshotSettingsStore()) {
        self.settingsStore = settingsStore
        // Must be registered exactly once before the .screenRecording pane is
        // used by the floating panel.
        PermissionFlowScreenRecordingStatus.register()
        self.controller = PermissionFlow.makeController()
    }

    isolated deinit {
        teardown()
    }

    // MARK: - Completion state

    /// Whether onboarding is fully satisfied. Persistence only counts when the
    /// live system checks still agree, so revoked permissions re-open the flow.
    var isComplete: Bool {
        guard settingsStore.load().onboardingCompleted else { return false }
        return allGatesGranted
    }

    private var allGatesGranted: Bool {
        gates.allSatisfy { $0.isGranted }
    }

    // MARK: - Entry points

    /// Begins onboarding only when it has not already been completed.
    func startIfNeeded() {
        guard !isComplete else { return }
        beginFlow()
    }

    /// Always (re)begins onboarding from the first ungranted gate, even if it
    /// was previously completed. Used by a menu item.
    func startFromUser() {
        beginFlow()
    }

    // MARK: - Flow control

    private func beginFlow() {
        installDidBecomeActiveObserverIfNeeded()

        guard let index = firstUngrantedGateIndex() else {
            // Nothing left to grant — record completion and stop nagging.
            finish()
            return
        }
        activateGate(at: index)
    }

    private func firstUngrantedGateIndex() -> Int? {
        gates.firstIndex { !$0.isGranted }
    }

    private func activateGate(at index: Int) {
        guard gates.indices.contains(index) else {
            finish()
            return
        }

        let gate = gates[index]

        // The gate may already be granted (e.g. the user granted it out of
        // band) — skip straight to the next one.
        guard !gate.isGranted else {
            advance(after: index)
            return
        }

        activeGateIndex = index

        // Opens System Settings AND shows the floating drag panel.
        controller.authorize(pane: gate.pane, suggestedAppURLs: [Bundle.main.bundleURL])
        startPolling()
    }

    private func advance(after index: Int) {
        let next = index + 1
        if gates.indices.contains(next) {
            activateGate(at: next)
        } else {
            finish()
        }
    }

    /// Handles the active gate becoming granted: tears down the polling and
    /// floating panel, then either advances or shows the relaunch step.
    private func handleActiveGateGranted() {
        guard let index = activeGateIndex else { return }
        let gate = gates[index]

        stopPolling()
        activeGateIndex = nil
        controller.closePanel(returnToPreviousApp: true)

        guard gate.requiresRelaunchAfterGrant else {
            advance(after: index)
            return
        }

        // The capture stack needs a fresh process. Persist progress first so
        // the relaunched instance does not re-nag, then offer the relaunch.
        persistCompletionIfAllGranted()
        presentRelaunchStep()
    }

    private func finish() {
        persistCompletionIfAllGranted()
        teardown()
    }

    private func persistCompletionIfAllGranted() {
        guard allGatesGranted else { return }
        do {
            try settingsStore.mutate { $0.onboardingCompleted = true }
        } catch {
            AppLog.store.error("failed to persist onboarding completion: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Live polling

    private func startPolling() {
        stopPolling()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkActiveGate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkActiveGate() {
        guard let index = activeGateIndex, gates[index].isGranted else { return }
        handleActiveGateGranted()
    }

    // MARK: - Returning from System Settings

    private func installDidBecomeActiveObserverIfNeeded() {
        guard didBecomeActiveObserver == nil else { return }

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Re-check promptly when the user returns from System Settings,
            // without waiting for the next timer tick.
            Task { @MainActor [weak self] in
                self?.checkActiveGate()
            }
        }
    }

    // MARK: - Relaunch step

    private func presentRelaunchStep() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording granted — quit & reopen to finish setup"
        alert.informativeText = "Appshots needs a fresh launch before it can capture screenshots. Quit and reopen now to complete setup."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit & Reopen")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        } else {
            teardown()
        }
    }

    private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]

        do {
            try process.run()
        } catch {
            // Leave the current instance running so the user isn't stranded.
            teardown()
            return
        }
        NSApp.terminate(nil)
    }

    // MARK: - Teardown

    private func teardown() {
        stopPolling()
        activeGateIndex = nil

        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
            self.didBecomeActiveObserver = nil
        }
    }
}
