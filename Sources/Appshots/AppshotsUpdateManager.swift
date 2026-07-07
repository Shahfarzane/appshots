import AppKit
import AppshotsCore
import Foundation
import Observation
@preconcurrency import Sparkle

@MainActor
@Observable
final class AppshotsUpdateManager: NSObject {
    static let shared = AppshotsUpdateManager()

    enum UpdateState: Equatable {
        case checkForUpdate
        case downloadingUpdate
        case installUpdate
    }

    var updateState: UpdateState = .checkForUpdate
    var pendingUpdateVersion: String?
    var downloadingVersion: String?

    @ObservationIgnored private var installationBlock: (@Sendable () -> Void)?

    /// Live-reloads the `autoUpdate` setting into Sparkle when the shared config
    /// changes (e.g. a CLI `update auto off`), matching the trigger-key / sound
    /// live reload. Retained for the singleton's lifetime so delivery keeps working.
    @ObservationIgnored private var settingsToken: AppshotSettingsObservationToken?

    @ObservationIgnored lazy var updaterController: SPUStandardUpdaterController = {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        applyAutomaticUpdatePolicy(to: controller.updater)
        controller.startUpdater()
        return controller
    }()

    private override init() {
        super.init()
        _ = updaterController
        settingsToken = AppshotSettingsStore.observe { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyAutomaticUpdatePolicy(to: self.updaterController.updater)
                Self.log("Sparkle auto-update policy reloaded: autoChecks=\(self.updaterController.updater.automaticallyChecksForUpdates)")
            }
        }
        log(
            "Sparkle updater initialized: " +
                "autoChecks=\(updaterController.updater.automaticallyChecksForUpdates) " +
                "autoDownloads=\(updaterController.updater.automaticallyDownloadsUpdates) " +
                "feed=\(updaterController.updater.feedURL?.absoluteString ?? "(nil)")"
        )
    }

    var canInstallUpdate: Bool {
        updateState == .installUpdate && installationBlock != nil
    }

    var statusText: String {
        switch updateState {
        case .checkForUpdate:
            "Automatic checks are enabled."
        case .downloadingUpdate:
            if let downloadingVersion {
                "Downloading \(downloadingVersion)."
            } else {
                "Downloading the latest version."
            }
        case .installUpdate:
            if let pendingUpdateVersion {
                "\(pendingUpdateVersion) is ready to install."
            } else {
                "An update is ready to install."
            }
        }
    }

    func checkForUpdates() {
        guard !updaterController.updater.sessionInProgress else { return }
        updaterController.checkForUpdates(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func installUpdate() {
        guard let installationBlock else {
            checkForUpdates()
            return
        }

        self.installationBlock = nil
        pendingUpdateVersion = nil
        updateState = .checkForUpdate
        // Sparkle's immediate-install handler installs AND relaunches the app
        // itself (SPUUpdaterDelegate.h); relaunching here too would race the
        // installer and spawn a second instance of the old bundle.
        installationBlock()
    }

    func runPrimaryAction() {
        if canInstallUpdate {
            installUpdate()
        } else {
            checkForUpdates()
        }
    }

    private func applyAutomaticUpdatePolicy(to updater: SPUUpdater) {
        // Honor the user's `autoUpdate` setting (defaults to true) instead of
        // force-enabling on every launch. Sparkle's own SU* keys stay owned by
        // Sparkle/UserDefaults.
        let autoUpdate = AppshotSettingsStore().load().autoUpdate
        updater.automaticallyChecksForUpdates = autoUpdate
        updater.automaticallyDownloadsUpdates = autoUpdate
    }

    nonisolated static func log(_ message: String) {
        AppLog.updates.notice("\(message, privacy: .public)")
    }

    private func log(_ message: String) {
        Self.log(message)
    }
}

extension AppshotsUpdateManager: SPUStandardUserDriverDelegate {
    nonisolated func standardUserDriverDidShowModalAlert() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                for window in NSApp.windows {
                    guard let controller = window.windowController,
                          controller.className == "SUStatusController"
                    else { continue }
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
}

extension AppshotsUpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(_: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with _: NSMutableURLRequest) {
        Self.log("Starting update download")
        Task { @MainActor in
            downloadingVersion = item.displayVersionString
            updateState = .downloadingUpdate
        }
    }

    nonisolated func updater(_: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Self.log("Update downloaded: \(item.displayVersionString)")
    }

    nonisolated func updater(_: SPUUpdater, failedToDownloadUpdate _: SUAppcastItem, error: Error) {
        Self.log("Failed to download update: \(error.localizedDescription)")
        Task { @MainActor in
            downloadingVersion = nil
            updateState = .checkForUpdate
        }
    }

    nonisolated func userDidCancelDownload(_: SPUUpdater) {
        Self.log("User canceled update download")
        Task { @MainActor in
            downloadingVersion = nil
            updateState = .checkForUpdate
        }
    }

    nonisolated func updaterDidNotFindUpdate(_: SPUUpdater) {
        Self.log("No update available")
        Task { @MainActor in
            updateState = .checkForUpdate
        }
    }

    nonisolated func updater(_: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Self.log("Found valid update: version=\(item.displayVersionString)")
    }

    nonisolated func updater(
        _: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock: @escaping @Sendable () -> Void
    ) -> Bool {
        Task { @MainActor in
            downloadingVersion = nil
            pendingUpdateVersion = item.displayVersionString
            installationBlock = immediateInstallationBlock
            updateState = .installUpdate
        }
        return true
    }

    nonisolated func updater(
        _: SPUUpdater,
        didFinishUpdateCycleFor _: SPUUpdateCheck,
        error: (any Error)?
    ) {
        if let error {
            Self.log(error.localizedDescription)
        }
    }

    nonisolated func updater(_: SPUUpdater, didAbortWithError error: Error) {
        Self.log("Update aborted: \(error.localizedDescription)")
        Task { @MainActor in
            updateState = .checkForUpdate
        }
    }

    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        true
    }
}
