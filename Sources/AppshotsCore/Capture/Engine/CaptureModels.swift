import AppKit
import ApplicationServices
import Foundation

struct CGWindowSnapshot {
    let windowID: Int
    let name: String
    let layer: Int
    let bounds: CGRect
}

struct RuntimeAXNode {
    let index: Int
    let depth: Int
    let element: AXUIElement
    let role: String
    let subrole: String
    let title: String
    let description: String
    let value: Any?
    let help: String
    let identifier: String
    let url: URL?
    let enabled: Bool?
    let selected: Bool?
    let expanded: Bool?
    let focused: Bool?
    let frame: CGRect?
    let actions: [String]
    let isValueSettable: Bool
    let valueTypeDescription: String?
    let collectionSummary: String?
}

enum RuntimeSurfaceKind: String {
    case window
    case status
    case menu
}

struct RuntimeAppSnapshot {
    let app: NSRunningApplication
    let surfaceKind: RuntimeSurfaceKind
    let windowID: Int
    let windowTitle: String
    let windowFrame: CGRect
    let nodes: [RuntimeAXNode]
    let focusedElementIndex: Int?
    let selectedText: String?
    let screenshotURL: URL?
    let screenshotSize: CGSize?
    let fingerprint: String

    init(
        app: NSRunningApplication,
        surfaceKind: RuntimeSurfaceKind = .window,
        windowID: Int,
        windowTitle: String,
        windowFrame: CGRect,
        nodes: [RuntimeAXNode],
        focusedElementIndex: Int?,
        selectedText: String?,
        screenshotURL: URL?,
        screenshotSize: CGSize?,
        fingerprint: String
    ) {
        self.app = app
        self.surfaceKind = surfaceKind
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.windowFrame = windowFrame
        self.nodes = nodes
        self.focusedElementIndex = focusedElementIndex
        self.selectedText = selectedText
        self.screenshotURL = screenshotURL
        self.screenshotSize = screenshotSize
        self.fingerprint = fingerprint
    }

    func node(index: Int) throws -> RuntimeAXNode {
        guard let node = nodes.first(where: { $0.index == index }) else {
            throw CaptureError.elementNotFound(index)
        }
        return node
    }
}

struct WindowSelection {
    var titleSubstring: String? = nil
    var windowID: Int? = nil
}

public struct WindowCaptureTarget: Sendable {
    public var surface: AppshotCaptureSurface
    public var windowID: Int
    public var windowTitle: String
    public var windowFrame: CGRect

    public init(
        surface: AppshotCaptureSurface,
        windowID: Int,
        windowTitle: String,
        windowFrame: CGRect
    ) {
        self.surface = surface
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.windowFrame = windowFrame
    }
}

public struct ScreenshotCaptureResult: Sendable {
    public var windowID: Int
    public var url: URL
    public var size: CGSize

    public init(windowID: Int, url: URL, size: CGSize) {
        self.windowID = windowID
        self.url = url
        self.size = size
    }
}

public struct CaptureEventSink: Sendable {
    public var metadataResolved: @Sendable (WindowCaptureTarget) -> Void
    public var screenshotCaptured: @Sendable (ScreenshotCaptureResult) -> Void

    public init(
        metadataResolved: @escaping @Sendable (WindowCaptureTarget) -> Void = { _ in },
        screenshotCaptured: @escaping @Sendable (ScreenshotCaptureResult) -> Void = { _ in }
    ) {
        self.metadataResolved = metadataResolved
        self.screenshotCaptured = screenshotCaptured
    }
}
