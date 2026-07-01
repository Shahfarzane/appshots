import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

private struct WindowCandidate {
    let element: AXUIElement
    let title: String
    let frame: CGRect
    let cgWindow: CGWindowSnapshot
    let isMain: Bool
    let isFocused: Bool
}

extension AccessibilityCaptureEngine {
    static func resolveRunningApplication(matching identifier: String) throws -> NSRunningApplication {
        if let app = resolveRunningApplicationIfAvailable(matching: identifier) {
            return app
        }

        throw CaptureError.appNotRunning(identifier)
    }

    static func resolveWindow(
        in appElement: AXUIElement,
        app: NSRunningApplication,
        titleSubstring: String?,
        preferredWindowID: Int?,
        preferredWindowFrame: CGRect? = nil,
        requirePreferredWindowID: Bool = false
    ) throws -> (element: AXUIElement, title: String, frame: CGRect, cgWindow: CGWindowSnapshot) {
        let candidates = windowCandidates(
            in: appElement,
            app: app,
            preferredWindowID: preferredWindowID
        )

        if let preferredWindowID,
           let exact = candidates.first(where: { $0.cgWindow.windowID == preferredWindowID })
        {
            return resolvedWindow(exact)
        }

        if let preferredWindowID, requirePreferredWindowID {
            throw CaptureError.windowNotFound(
                app: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                title: "window_id=\(preferredWindowID)"
            )
        }

        if let preferredWindowFrame,
           let best = bestCandidateByFrame(candidates, hint: preferredWindowFrame)
        {
            return resolvedWindow(best)
        }

        let filtered: [WindowCandidate] = if let titleSubstring, titleSubstring.isEmpty == false {
            candidates.filter { candidate in
                candidate.title.localizedCaseInsensitiveContains(titleSubstring)
            }
        } else {
            candidates
        }

        if let main = filtered.first(where: { $0.isMain }) {
            return resolvedWindow(main)
        }

        if let focused = filtered.first(where: { $0.isFocused }) {
            return resolvedWindow(focused)
        }

        if let first = filtered.first {
            return resolvedWindow(first)
        }

        throw CaptureError.windowNotFound(
            app: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
            title: titleSubstring
        )
    }

    private static func windowCandidates(
        in appElement: AXUIElement,
        app: NSRunningApplication,
        preferredWindowID: Int? = nil
    ) -> [WindowCandidate] {
        let windows = mergeAXWindowCandidates(
            listedWindows: cuAttribute(appElement, name: kAXWindowsAttribute as String) as [AXUIElement]? ?? [],
            focusedWindow: cuAttribute(appElement, name: kAXFocusedWindowAttribute as String) as AXUIElement?,
            mainWindow: cuAttribute(appElement, name: kAXMainWindowAttribute as String) as AXUIElement?
        )
        let cgWindows = cuCGWindows(for: app.processIdentifier)

        var candidates: [WindowCandidate] = []

        for window in windows {
            guard let frame = cuFrame(window) else {
                continue
            }

            let title = cuTitle(window)
            let matchingWindow = matchCGWindow(
                axWindow: window,
                candidates: cgWindows,
                preferredWindowID: preferredWindowID,
                title: title,
                frame: frame
            )

            guard let cgWindow = matchingWindow else {
                continue
            }

            candidates.append(WindowCandidate(
                element: window,
                title: title,
                frame: frame,
                cgWindow: cgWindow,
                isMain: cuBoolAttribute(window, name: kAXMainAttribute as String) == true,
                isFocused: cuBoolAttribute(window, name: kAXFocusedAttribute as String) == true
            ))
        }

        return candidates
    }

    private static func resolvedWindow(
        _ candidate: WindowCandidate
    ) -> (element: AXUIElement, title: String, frame: CGRect, cgWindow: CGWindowSnapshot) {
        (candidate.element, candidate.title, candidate.frame, candidate.cgWindow)
    }

    private static func bestCandidateByFrame(
        _ candidates: [WindowCandidate],
        hint: CGRect
    ) -> WindowCandidate? {
        func score(_ frame: CGRect) -> CGFloat {
            let dx = frame.midX - hint.midX
            let dy = frame.midY - hint.midY
            let dw = frame.width - hint.width
            let dh = frame.height - hint.height
            return sqrt(dx * dx + dy * dy) + abs(dw) + abs(dh)
        }
        return candidates
            .map { ($0, score($0.frame)) }
            .min(by: { $0.1 < $1.1 })?.0
    }

    private static func matchCGWindow(
        axWindow: AXUIElement,
        candidates: [CGWindowSnapshot],
        preferredWindowID: Int?,
        title: String,
        frame: CGRect
    ) -> CGWindowSnapshot? {
        if let exactWindowID = AXWindowIDResolver.cgWindowID(forAXWindow: axWindow),
           let exact = candidates.first(where: { $0.windowID == Int(exactWindowID) })
        {
            return exact
        }

        if let preferredWindowID,
           let preferred = candidates.first(where: { $0.windowID == preferredWindowID }),
           nearlyEqualRects(preferred.bounds, frame, tolerance: 4)
        {
            return preferred
        }

        if title.isEmpty == false {
            let sameTitle = candidates.filter {
                $0.name.localizedCaseInsensitiveContains(title)
            }
            if let frameMatch = sameTitle.first(where: {
                nearlyEqualRects($0.bounds, frame)
            }) {
                return frameMatch
            }
            if let firstTitle = sameTitle.first {
                return firstTitle
            }
        }

        return candidates.first(where: { nearlyEqualRects($0.bounds, frame) }) ??
            candidates.first(where: { $0.layer == 0 })
    }
}

extension AccessibilityCaptureEngine {
    static func resolveRunningApplicationIfAvailable(matching identifier: String) -> NSRunningApplication? {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }

        if let byBundleID = runningApps.first(where: { $0.bundleIdentifier == identifier }) {
            return byBundleID
        }

        if let byName = runningApps.first(where: {
            ($0.localizedName ?? "").localizedCaseInsensitiveCompare(identifier) == .orderedSame
        }) {
            return byName
        }

        if let containsName = runningApps.first(where: {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains(identifier)
        }) {
            return containsName
        }

        return nil
    }
}

enum AXWindowIDResolver {
    private typealias AXUIElementGetWindowFn = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<CGWindowID>
    ) -> AXError

    private static let getWindowForAXElement: AXUIElementGetWindowFn? = {
        _ = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
            RTLD_LAZY
        )
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            return nil
        }
        return unsafeBitCast(symbol, to: AXUIElementGetWindowFn.self)
    }()

    static func cgWindowID(forAXWindow element: AXUIElement) -> CGWindowID? {
        guard let getWindowForAXElement else { return nil }
        var windowID: CGWindowID = 0
        guard getWindowForAXElement(element, &windowID) == .success, windowID != 0 else {
            return nil
        }
        return windowID
    }
}
