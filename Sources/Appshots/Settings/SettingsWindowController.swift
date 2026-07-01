import AppKit
import Luminare
import Observation
import SwiftUI

/// Holds the selected settings destination. Mirrors the role of Loop's
/// `SettingsWindowManager.currentTab`, kept minimal for Appshots.
@MainActor
@Observable
final class SettingsWindowModel {
    var currentTab: SettingsTab = .history
}

/// Owns the single Loop-style settings `LuminareWindow` and its lifecycle.
/// Modeled on Loop's `SettingsWindowManager`, minus the SkyLight private-API
/// blur (Luminare's own materialized chrome stands in) and the live preview.
///
/// Appshots is `LSUIElement`, so the activation policy flips to `.regular` while
/// the window is open (matching Loop) and back to the user's Dock preference
/// (`showInDock`) on close — `.accessory` unless a Dock icon is enabled.
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

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Return to the user's Dock preference once the settings window is
        // dismissed: menu-bar-only unless a Dock icon is enabled.
        NSApp.setActivationPolicy(appModel.showInDock ? .regular : .accessory)
    }
}
