import AppKit
import Luminare
import SwiftUI

/// Owns the single Loop-style settings `LuminareWindow` and its lifecycle.
/// Modeled on Loop's `SettingsWindowManager`, minus the SkyLight private-API
/// blur (Luminare's own materialized chrome stands in) and the live preview.
///
/// Appshots is `LSUIElement`, so the activation policy flips to `.regular` while
/// the window is open (matching Loop) and back to `.accessory` on close.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let appModel: AppshotsModel
    private let model = SettingsWindowModel()
    private var controller: NSWindowController?

    init(appModel: AppshotsModel) {
        self.appModel = appModel
        super.init()
    }

    func show(selecting tab: SettingsTab? = nil) {
        if let tab {
            model.currentTab = tab
        }

        if controller == nil {
            let window = LuminareWindow {
                SettingsContentView(model: self.model, appModel: self.appModel)
                    .frame(height: AppshotsTheme.Size.settingsHeight)
            }
            window.title = "Appshots Settings"
            window.delegate = self
            controller = NSWindowController(window: window)
        }

        NSApp.setActivationPolicy(.regular)
        controller?.showWindow(nil)
        controller?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        controller?.close()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Return to menu-bar-only once the settings window is dismissed.
        NSApp.setActivationPolicy(.accessory)
    }
}
