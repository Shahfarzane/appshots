import AppKit
import AppshotsCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppshotsModel()
    private let frontmostTracker = FrontmostAppTracker()
    private let captureAnimator = AppshotCaptureAnimator()
    private let onboardingCoordinator = OnboardingCoordinator()
    private lazy var settingsWindowController = SettingsWindowController(appModel: model)
    private lazy var previewWindowController = AppshotPreviewWindowController(model: model)
    private var hotKeyMonitor: AppshotsHotKeyMonitor?
    /// Cross-process hot-key lock, held for the app lifetime while the GUI owns
    /// the hot key (`.gui`/`.none`) and released when yielding to the daemon
    /// (`.headless`) or on termination, so exactly one process hosts the chord.
    private let hotKeyLock = HotKeyLock()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var didBecomeActiveObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.lifecycle.notice("app did finish launching version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?", privacy: .public)")
        frontmostTracker.start()
        model.frontmostTracker = frontmostTracker
        model.showPermissionPanel = { [weak self] in
            self?.onboardingCoordinator.startFromUser()
        }
        model.openSettings = { [weak self] in
            self?.settingsWindowController.show()
        }
        model.isSettingsWindowVisible = { [weak self] in
            self?.settingsWindowController.isWindowVisible ?? false
        }
        model.openPreview = { [weak self] record in
            self?.previewWindowController.show(record)
        }
        model.playCaptureAnimation = { [weak self] record, image in
            guard let self else { return }
            captureAnimator.animate(
                record: record,
                image: image,
                destinationPoint: statusItemIconCenterPoint()
            )
        }
        model.playPendingCaptureAnimation = { [weak self] windowFrame, image, appName, bundleID in
            guard let self else { return }
            captureAnimator.animate(
                windowFrame: windowFrame,
                image: image,
                appName: appName,
                bundleID: bundleID,
                destinationPoint: statusItemIconCenterPoint()
            )
        }
        model.onTriggerKeyChange = { [weak self] triggerKey in
            self?.hotKeyMonitor?.updateTriggerKey(triggerKey)
        }
        model.setHotKeyMonitorActive = { [weak self] active in
            guard let self else { return }
            if active {
                // Resume only when the GUI owns the chord for the current
                // startup mode: a canceled trigger recording in headless mode
                // must not re-arm alongside the daemon (double capture).
                if model.shouldGUIOwnHotKey {
                    hotKeyMonitor?.start()
                }
            } else {
                hotKeyMonitor?.stop()
            }
        }
        model.setHotKeyOwnership = { [weak self] own in
            guard let self else { return }
            if own {
                armHotKeyOnceLockAcquired()
            } else {
                // Yield to the headless daemon: stop listening, drop the lock.
                hotKeyMonitor?.stop()
                hotKeyLock.release()
            }
        }
        model.startSession()
        // Reconcile launch-at-login against config.json's startupMode, then keep
        // the login-item status fresh whenever the app is reactivated (the user
        // may toggle it in System Settings out of band).
        model.reconcileStartupMode()
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refreshStartupStatus()
            }
        }
        _ = AppshotsUpdateManager.shared

        setupStatusItem()
        // Debug affordance: launch with APPSHOTS_DEBUG_OPEN_SETTINGS set to jump
        // straight to the settings window (skips onboarding). The value may name a
        // tab (general/mcp/history/about) to preselect. Production-harmless.
        if let raw = ProcessInfo.processInfo.environment["APPSHOTS_DEBUG_OPEN_SETTINGS"] {
            settingsWindowController.show(selecting: SettingsTab(rawValue: raw))
        } else {
            onboardingCoordinator.startIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupHotKeyMonitor()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
        hotKeyLock.release()
        frontmostTracker.stop()
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
            self.didBecomeActiveObserver = nil
        }
        model.endSession()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Template glyph matching the app icon (viewfinder + centre dot); tints
        // for light/dark menu bars automatically.
        let icon = NSImage(systemSymbolName: "dot.viewfinder", accessibilityDescription: "Appshots")
        icon?.isTemplate = true
        item.button?.image = icon
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func ensurePopover() -> NSPopover {
        if let popover {
            return popover
        }

        let popover = NSPopover()
        popover.behavior = .transient
        // The SwiftUI view sets a fixed width and content-driven height; let the
        // hosting controller drive the popover size so it fits its content.
        let hostingController = NSHostingController(rootView: AppshotsPopoverView(model: model))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        self.popover = popover
        return popover
    }

    private func setupHotKeyMonitor() {
        guard hotKeyMonitor == nil else { return }

        let monitor = AppshotsHotKeyMonitor(
            triggerKey: model.triggerKey,
            onTrigger: { [weak self] in
                Task { @MainActor in
                    self?.model.captureFrontmostApp()
                }
            }
        )
        hotKeyMonitor = monitor
        // Arm only when this process owns the hot key for the current startup
        // mode; in headless mode the daemon owns it and the GUI stays silent.
        if model.shouldGUIOwnHotKey {
            armHotKeyOnceLockAcquired()
        }
    }

    /// Arms the monitor only once the cross-process lock is actually held,
    /// retrying briefly: during a headless→gui transition the daemon may still
    /// hold the flock for a moment after the settings notification, and arming
    /// without it would double-fire the chord (one press, two captures).
    private func armHotKeyOnceLockAcquired(attempt: Int = 0) {
        guard model.shouldGUIOwnHotKey else { return }
        if hotKeyLock.tryAcquire() {
            hotKeyMonitor?.start()
        } else if attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.armHotKeyOnceLockAcquired(attempt: attempt + 1)
            }
        } else {
            AppLog.lifecycle.error("hot-key lock still held elsewhere; GUI monitor not armed")
        }
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)

        if isRightClick {
            showStatusMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: Any?) {
        let popover = ensurePopover()
        model.refreshPermissions()

        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showStatusMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.addItem(menuItem("Settings…", #selector(openSettings)))
        menu.addItem(menuItem("History…", #selector(openHistory)))
        menu.addItem(menuItem("Setup Permissions…", #selector(openOnboarding)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Appshots", #selector(quitApp)))

        // Attach transiently so AppKit anchors the menu directly under the
        // status item, then detach so left-click still toggles the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openOnboarding() { onboardingCoordinator.startFromUser() }
    @objc private func openSettings() { settingsWindowController.show() }
    @objc private func openHistory() { settingsWindowController.show(selecting: .history) }
    @objc private func quitApp() { model.quit() }

    private func showPopover() {
        let popover = ensurePopover()
        guard let button = statusItem?.button, popover.isShown == false else {
            return
        }

        model.refreshPermissions()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func statusItemIconCenterPoint() -> CGPoint? {
        guard let button = statusItem?.button,
              let window = button.window
        else {
            return nil
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonFrameInWindow)
        return CGPoint(x: buttonFrameOnScreen.midX, y: buttonFrameOnScreen.midY)
    }
}
