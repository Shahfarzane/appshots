import AppKit
import SwiftUI

/// Base controller that owns a single SwiftUI-backed `NSWindow` and its
/// show lifecycle. Subclasses supply only the window's content, title, size,
/// and style; the shared `show()` creates the window on demand, centers it,
/// and brings the app forward.
@MainActor
class HostingWindowController: NSObject {
    private(set) var window: NSWindow?

    // MARK: Overridable window configuration

    /// Title shown in the window's titlebar.
    var windowTitle: String { "" }

    /// Initial content size used for the window's content rect.
    var contentSize: NSSize { NSSize(width: 480, height: 360) }

    /// Style mask applied when the window is created.
    var styleMask: NSWindow.StyleMask { [.titled, .closable, .miniaturizable, .resizable] }

    /// Build the SwiftUI-backed content view controller. Override to provide
    /// the root view. The default is an empty placeholder for subclasses that
    /// assign content later (e.g. when it depends on per-show input).
    func makeContentViewController() -> NSViewController {
        NSViewController()
    }

    /// Hook for additional per-window configuration (minSize, level, etc.).
    func configureWindow(_ window: NSWindow) {}

    // MARK: Lifecycle

    /// Returns the existing window, lazily creating it if needed.
    @discardableResult
    func ensureWindow() -> NSWindow {
        if let window { return window }
        let window = makeWindow()
        self.window = window
        return window
    }

    func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.contentViewController = makeContentViewController()
        window.isReleasedWhenClosed = false
        configureWindow(window)
        return window
    }
}
