import AppKit
import AppshotsCore
import SwiftUI

@MainActor
final class AppshotPreviewWindowController: HostingWindowController {
    private let model: AppshotsModel

    init(model: AppshotsModel) {
        self.model = model
        super.init()
    }

    override var styleMask: NSWindow.StyleMask {
        [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    }

    override var contentSize: NSSize {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width = min(1280, visible.width * 0.88)
        let height = min(860, visible.height * 0.9)
        return NSSize(width: width, height: height)
    }

    override func configureWindow(_ window: NSWindow) {
        window.minSize = NSSize(width: 720, height: 480)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        // Normal level: a full-screen preview should not hover above other apps
        // when the user switches away.
        window.level = .normal
    }

    func show(_ record: AppshotRecord) {
        let window = ensureWindow()

        window.title = record.appName.isEmpty ? "Appshot Preview" : "\(record.appName) — Appshot"
        window.contentViewController = NSHostingController(
            rootView: AppshotPreviewView(
                record: record,
                model: model,
                onClose: { [weak self] in self?.window?.close() }
            )
        )

        // Fill the whole visible screen (visibleFrame already excludes the menu
        // bar / notch, so safe areas are respected).
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            window.setFrame(visible, display: true)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
