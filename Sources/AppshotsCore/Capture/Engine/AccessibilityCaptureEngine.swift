import AppKit
import ApplicationServices
import CryptoKit
import Foundation

enum AccessibilityCaptureEngine {
    typealias ResolvedWindowMatch = (
        element: AXUIElement,
        title: String,
        frame: CGRect,
        cgWindow: CGWindowSnapshot
    )

    private struct SnapshotSurfaceScan {
        let appElement: AXUIElement
        let focusedElement: AXUIElement?
        let selectedText: String?
        let statusMenuExtras: [AXUIElement]
        let transientMenuWindowFrame: CGRect?
        let windowMatch: ResolvedWindowMatch?
        let windowResolutionError: CaptureError?
    }

    private static let runtimeReuseCache = RuntimeSnapshotReuseCache()

    static var sameWindowAXReuseRequiresFullRecapture: Bool {
        true
    }

    static func captureSnapshot(
        appIdentifier: String,
        selection: WindowSelection = .init(),
        includeScreenshot: Bool,
        screenshotCompression: ScreenshotCompression = .foregroundDefault,
        filterVisibleNodes: Bool = true,
        eventSink: CaptureEventSink? = nil
    ) throws -> RuntimeAppSnapshot {
        guard AXIsProcessTrusted() else {
            throw CaptureError.accessibilityPermissionDenied
        }

        let app = try resolveRunningApplication(matching: appIdentifier)
        return try captureSnapshot(
            app: app,
            selection: selection,
            includeScreenshot: includeScreenshot,
            screenshotCompression: screenshotCompression,
            filterVisibleNodes: filterVisibleNodes,
            eventSink: eventSink
        )
    }

    /// Persists one snapshot and derives both the formatted output and the
    /// structured state from it, sharing a single snapshot save so the
    /// accessibility tree is only walked once.
    static func persistFormatAndBuildState(
        snapshot: RuntimeAppSnapshot,
        options: CaptureOptions = .default
    ) throws -> (output: CaptureOutput, state: CapturedAppState) {
        let metadata = try SnapshotCacheStore.save(snapshot: snapshot)
        let output = formattedState(snapshot: snapshot, metadata: metadata, options: options)
        let state = structuredState(snapshot: snapshot, metadata: metadata)
        return (output, state)
    }

    static func structuredState(
        snapshot: RuntimeAppSnapshot,
        metadata: CaptureMetadata
    ) -> CapturedAppState {
        let parents = parentIndicesFromDepths(snapshot.nodes.map(\.depth))
        let nodes = snapshot.nodes.enumerated().map { i, node in
            AXNode(
                index: node.index,
                parentIndex: parents[i],
                depth: node.depth,
                role: node.role,
                subrole: node.subrole,
                title: node.title,
                description: node.description,
                value: stringValueOrNil(node.value),
                help: node.help,
                identifier: node.identifier,
                url: node.url?.absoluteString,
                enabled: node.enabled,
                selected: node.selected,
                expanded: node.expanded,
                focused: node.focused,
                frame: node.frame.map(CGRectCodable.init),
                actions: node.actions,
                isValueSettable: node.isValueSettable,
                valueTypeDescription: node.valueTypeDescription,
                collectionSummary: node.collectionSummary
            )
        }
        return CapturedAppState(
            metadata: metadata,
            surface: snapshot.surfaceKind.rawValue,
            focusedElementIndex: snapshot.focusedElementIndex,
            selectedText: snapshot.selectedText,
            nodes: nodes
        )
    }

    static func formattedState(
        snapshot: RuntimeAppSnapshot,
        metadata: CaptureMetadata,
        options: CaptureOptions = .default
    ) -> CaptureOutput {
        let stateDump = AppStateTextFormatter.format(
            snapshot: snapshot,
            includeElementIndexes: options.includeElementIndexes,
            preserveTextAreaNewlines: options.preserveTextAreaNewlines
        )
        let surfaceHint = surfaceHintText(for: snapshot)
        var text = """
        <app_state surface="\(snapshot.surfaceKind.rawValue)">
        \(surfaceHint)
        \(stateDump)
        </app_state>
        """

        if let screenshotPath = metadata.screenshotPath {
            text += "\nScreenshot: \(screenshotPath)"
        }

        if let screenshotSize = metadata.screenshotSize {
            text += "\nScreenshotSize: \(Int(screenshotSize.width))x\(Int(screenshotSize.height))"
        }

        return CaptureOutput(text: text, metadata: metadata)
    }

    private static func surfaceHintText(for snapshot: RuntimeAppSnapshot) -> String {
        switch snapshot.surfaceKind {
        case .window:
            return "Surface: window. The state below is the app window plus the app's top-level menu bar items."
        case .status:
            return "Surface: status. No app window is available; the state below contains the app's status item."
        case .menu:
            return "Surface: menu. An app menu is currently open; the state below contains the open menu."
        }
    }

    private static func captureSnapshot(
        app: NSRunningApplication,
        selection: WindowSelection,
        includeScreenshot: Bool,
        screenshotCompression: ScreenshotCompression,
        preferredWindowID: Int? = nil,
        preferredWindowFrame: CGRect? = nil,
        filterVisibleNodes: Bool = true,
        eventSink: CaptureEventSink? = nil
    ) throws -> RuntimeAppSnapshot {
        try runAXRead {
            Result {
                try captureSnapshotOnAXReadQueue(
                    app: app,
                    selection: selection,
                    includeScreenshot: includeScreenshot,
                    screenshotCompression: screenshotCompression,
                    preferredWindowID: preferredWindowID,
                    preferredWindowFrame: preferredWindowFrame,
                    filterVisibleNodes: filterVisibleNodes,
                    eventSink: eventSink
                )
            }
        }.get()
    }

    private static func captureSnapshotOnAXReadQueue(
        app: NSRunningApplication,
        selection: WindowSelection,
        includeScreenshot: Bool,
        screenshotCompression: ScreenshotCompression,
        preferredWindowID: Int?,
        preferredWindowFrame: CGRect?,
        filterVisibleNodes: Bool,
        eventSink: CaptureEventSink?
    ) throws -> RuntimeAppSnapshot {
        let scan = try AppshotCaptureMetricsContext.measure("app/window AX root resolve") {
            try scanSnapshotSurface(
                app: app,
                selection: selection,
                preferredWindowID: preferredWindowID,
                preferredWindowFrame: preferredWindowFrame
            )
        }
        guard let windowMatch = scan.windowMatch else {
            guard let error = scan.windowResolutionError,
                  case .windowNotFound = error,
                  selection.titleSubstring == nil,
                  selection.windowID == nil,
                  preferredWindowID == nil,
                  let statusSnapshot = statusSurfaceSnapshot(
                    app: app,
                    appElement: scan.appElement,
                    focusedElement: scan.focusedElement,
                    selectedText: scan.selectedText,
                    statusMenuExtras: scan.statusMenuExtras,
                    filterVisibleNodes: filterVisibleNodes
                  )
            else {
                throw scan.windowResolutionError ?? CaptureError.windowNotFound(
                    app: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                    title: selection.titleSubstring
                )
            }
            return statusSnapshot
        }

        if let menuSnapshot = menuSurfaceSnapshot(
            app: app,
            appElement: scan.appElement,
            windowMatch: windowMatch,
            focusedElement: scan.focusedElement,
            selectedText: scan.selectedText,
            statusMenuExtras: scan.statusMenuExtras,
            transientMenuWindowFrame: scan.transientMenuWindowFrame,
            filterVisibleNodes: filterVisibleNodes
        ) {
            return menuSnapshot
        }

        eventSink?.metadataResolved(WindowCaptureTarget(
            appName: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
            bundleID: app.bundleIdentifier ?? "",
            pid: app.processIdentifier,
            surface: .window,
            windowID: windowMatch.cgWindow.windowID,
            windowTitle: windowMatch.title,
            windowFrame: windowMatch.frame
        ))

        let pendingScreenshot = includeScreenshot
            ? PendingScreenshotCapture(
                windowID: windowMatch.cgWindow.windowID,
                compression: screenshotCompression,
                eventSink: eventSink
            )
            : nil

        let reuse = runtimeReuseCache.reuse(
            app: app,
            windowID: windowMatch.cgWindow.windowID,
            windowTitle: windowMatch.title,
            windowFrame: windowMatch.frame,
            selectedText: scan.selectedText,
            focusedElement: scan.focusedElement
        )
        let nodes: [RuntimeAXNode]
        let focusedIndex: Int?
        if let reuse, scan.transientMenuWindowFrame == nil {
            nodes = reuse.nodes
            focusedIndex = reuse.focusedElementIndex
            AppshotCaptureMetricsContext.mark("AX flatten tree", detail: "cache_hit")
            AppshotCaptureMetricsContext.setAXNodeCount(nodes.count)
        } else {
            nodes = AppshotCaptureMetricsContext.measure("AX flatten tree", detail: reuse?.reason ?? "cache_miss") {
                var flattened = flattenTree(
                    from: windowMatch.element,
                    focusedElement: scan.focusedElement,
                    visibleFrame: windowMatch.frame,
                    filterVisibleNodes: filterVisibleNodes
                )
                if scan.transientMenuWindowFrame != nil || scan.statusMenuExtras.isEmpty == false {
                    flattened.append(contentsOf: reindexedNodes(
                        menuBarNodes(
                            appElement: scan.appElement,
                            focusedElement: scan.focusedElement,
                            fallbackFrame: windowMatch.frame,
                            filterVisibleNodes: filterVisibleNodes
                        ),
                        startingAt: flattened.count
                    ))
                    flattened.append(contentsOf: reindexedNodes(
                        statusMenuExtraNodes(
                            statusMenuExtras: scan.statusMenuExtras,
                            focusedElement: scan.focusedElement,
                            fallbackFrame: windowMatch.frame,
                            filterVisibleNodes: filterVisibleNodes
                        ),
                        startingAt: flattened.count
                    ))
                }
                return flattened
            }
            AppshotCaptureMetricsContext.setAXNodeCount(nodes.count)
            focusedIndex = scan.focusedElement.flatMap { focused in
                nodes.first(where: { CFEqual($0.element, focused) })?.index
            }
        }

        let screenshotCapture = pendingScreenshot?.wait()

        let fingerprint = fingerprint(
            app: app,
            windowID: windowMatch.cgWindow.windowID,
            windowTitle: windowMatch.title,
            windowFrame: windowMatch.frame,
            nodes: nodes,
            focusedElementIndex: focusedIndex,
            selectedText: scan.selectedText
        )

        let snapshot = RuntimeAppSnapshot(
            app: app,
            surfaceKind: .window,
            windowID: windowMatch.cgWindow.windowID,
            windowTitle: windowMatch.title,
            windowFrame: windowMatch.frame,
            nodes: nodes,
            focusedElementIndex: focusedIndex,
            selectedText: scan.selectedText,
            screenshotURL: screenshotCapture?.url,
            screenshotSize: screenshotCapture?.size,
            fingerprint: fingerprint
        )
        runtimeReuseCache.store(snapshot)
        return snapshot
    }

    private static func scanSnapshotSurface(
        app: NSRunningApplication,
        selection: WindowSelection,
        preferredWindowID: Int?,
        preferredWindowFrame: CGRect?
    ) throws -> SnapshotSurfaceScan {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Bound each AX round-trip so a busy target app can't stall the whole capture; the default
        // timeout is effectively unbounded. Applies to every element resolved through this app.
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        AppshotCaptureMetricsContext.measure("Chromium activation") {
            ChromiumAccessibilityActivation.shared.activateIfNeeded(
                pid: app.processIdentifier,
                root: appElement
            )
        }
        let focusedElement = AppshotCaptureMetricsContext.measure("focused element / selected text") {
            cuAttribute(
                appElement,
                name: kAXFocusedUIElementAttribute as String
            ) as AXUIElement?
        }
        let selectedText = AppshotCaptureMetricsContext.measure("focused element / selected text") {
            focusedElement.flatMap {
                cuAttribute($0, name: kAXSelectedTextAttribute as String) as String?
            }
        }
        let statusAndMenu = AppshotCaptureMetricsContext.measure("status/menu detection") {
            (
                statusMenuExtras: statusMenuExtraCandidates(in: appElement),
                transientMenuWindowFrame: transientMenuWindowFrame(for: app.processIdentifier)
            )
        }

        do {
            let windowMatch = try AppshotCaptureMetricsContext.measure("window resolution") {
                try resolveWindow(
                    in: appElement,
                    app: app,
                    titleSubstring: selection.titleSubstring,
                    preferredWindowID: selection.windowID ?? preferredWindowID,
                    preferredWindowFrame: preferredWindowFrame,
                    requirePreferredWindowID: selection.windowID != nil
                )
            }
            return SnapshotSurfaceScan(
                appElement: appElement,
                focusedElement: focusedElement,
                selectedText: selectedText,
                statusMenuExtras: statusAndMenu.statusMenuExtras,
                transientMenuWindowFrame: statusAndMenu.transientMenuWindowFrame,
                windowMatch: windowMatch,
                windowResolutionError: nil
            )
        } catch let error as CaptureError {
            return SnapshotSurfaceScan(
                appElement: appElement,
                focusedElement: focusedElement,
                selectedText: selectedText,
                statusMenuExtras: statusAndMenu.statusMenuExtras,
                transientMenuWindowFrame: statusAndMenu.transientMenuWindowFrame,
                windowMatch: nil,
                windowResolutionError: error
            )
        }
    }

    static func runAXRead<T>(_ body: @escaping () -> T) -> T {
        body()
    }

    private final class PendingScreenshotCapture: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var result: (url: URL, size: CGSize)?

        init(
            windowID: Int,
            compression: ScreenshotCompression,
            eventSink: CaptureEventSink?
        ) {
            DispatchQueue.global(qos: .userInitiated).async {
                let capture = AppshotCaptureMetricsContext.measure("screenshot capture") {
                    BackgroundWindowCapture.captureWindowScreenshot(
                        windowID: windowID,
                        compression: compression
                    )
                }
                if let capture {
                    eventSink?.screenshotCaptured(ScreenshotCaptureResult(
                        windowID: windowID,
                        url: capture.url,
                        size: capture.size
                    ))
                }
                self.lock.withLock {
                    self.result = capture
                }
                self.semaphore.signal()
            }
        }

        func wait() -> (url: URL, size: CGSize)? {
            semaphore.wait()
            return lock.withLock { result }
        }
    }

    private final class RuntimeSnapshotReuseCache: @unchecked Sendable {
        private struct Entry {
            var bundleID: String
            var pid: pid_t
            var windowID: Int
            var windowTitle: String
            var windowFrame: CGRect
            var selectedText: String?
            var nodes: [RuntimeAXNode]
            var storedAt: Date
        }

        private let lock = NSLock()
        private var entry: Entry?
        private let ttl: TimeInterval = 2.0

        func reuse(
            app: NSRunningApplication,
            windowID: Int,
            windowTitle: String,
            windowFrame: CGRect,
            selectedText: String?,
            focusedElement: AXUIElement?
        ) -> (nodes: [RuntimeAXNode], focusedElementIndex: Int?, reason: String)? {
            guard AccessibilityCaptureEngine.sameWindowAXReuseRequiresFullRecapture == false else {
                return nil
            }
            return lock.withLock { () -> (nodes: [RuntimeAXNode], focusedElementIndex: Int?, reason: String)? in
                guard let entry,
                      Date().timeIntervalSince(entry.storedAt) <= ttl,
                      entry.pid == app.processIdentifier,
                      entry.bundleID == (app.bundleIdentifier ?? ""),
                      entry.windowID == windowID,
                      entry.windowTitle == windowTitle,
                      stableRectString(entry.windowFrame) == stableRectString(windowFrame),
                      entry.selectedText == selectedText
                else {
                    return nil
                }
                // The same window can change visible rows, terminal/browser/mail text, web content,
                // and node counts while these stable fields remain identical. Until reuse validates a
                // fresh dynamic fingerprint, fail closed and force a full AX walk.
                return nil
            }
        }

        func store(_ snapshot: RuntimeAppSnapshot) {
            guard snapshot.surfaceKind == .window else {
                return
            }
            lock.withLock {
                entry = Entry(
                    bundleID: snapshot.app.bundleIdentifier ?? "",
                    pid: snapshot.app.processIdentifier,
                    windowID: snapshot.windowID,
                    windowTitle: snapshot.windowTitle,
                    windowFrame: snapshot.windowFrame,
                    selectedText: snapshot.selectedText,
                    nodes: snapshot.nodes,
                    storedAt: Date()
                )
            }
        }
    }

    private static let prewarmQueue = DispatchQueue(
        label: "ceo.nerd.appshots.capture.prewarm",
        qos: .utility
    )

    /// Warms a target app's accessibility connection in the background so the FIRST capture of
    /// that app doesn't pay the one-time cost: establishing the AX connection and the
    /// `AXEnhancedUserInterface` tree rebuild. Call this when an app becomes frontmost; by the time
    /// the user captures, the tree is warm. Idempotent and cheap once an app is already warm.
    public static func prewarm(pid: pid_t) {
        prewarmQueue.async {
            let started = DispatchTime.now()
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.5)
            // Same activation attributes the capture path applies, set early so the (expensive,
            // first-time) enhanced-accessibility rebuild happens here instead of during capture.
            _ = AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            _ = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            // Touch the same shallow app/window attributes the real capture resolves before the
            // expensive full tree walk. This keeps prewarm cheap while moving first-window AX
            // connection and attribute-cache costs out of the hotkey path.
            _ = cuAttribute(appElement, name: kAXFocusedUIElementAttribute as String) as AXUIElement?
            let focusedWindow = cuAttribute(appElement, name: kAXFocusedWindowAttribute as String) as AXUIElement?
            let windows = cuAttribute(appElement, name: kAXWindowsAttribute as String) as [AXUIElement]? ?? []
            if let warmWindow = focusedWindow ?? windows.first {
                _ = cuTitle(warmWindow)
                _ = cuFrame(warmWindow)
                _ = cuChildElements(warmWindow)
            }
            _ = cuChildElements(appElement)
            let elapsedMs = (DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
            AppLog.capture.debug("accessibility prewarm finished pid=\(pid, privacy: .public) windows=\(windows.count, privacy: .public) ms=\(elapsedMs, privacy: .public)")
        }
    }

    private static func transientMenuWindowFrame(for pid: pid_t) -> CGRect? {
        let popupMenuLevel = CGWindowLevelForKey(.popUpMenuWindow)
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]
        else {
            return nil
        }

        for window in windows {
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard ownerPID == pid, layer == popupMenuLevel else {
                continue
            }
            guard let rawBounds = window[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            let frame = CGRect(
                x: rawBounds["X"] ?? 0,
                y: rawBounds["Y"] ?? 0,
                width: rawBounds["Width"] ?? 0,
                height: rawBounds["Height"] ?? 0
            )
            guard frame.width > 0, frame.height > 0 else {
                continue
            }
            return frame
        }

        return nil
    }

    private static func menuBarNodes(
        appElement: AXUIElement,
        focusedElement: AXUIElement?,
        fallbackFrame: CGRect,
        filterVisibleNodes: Bool
    ) -> [RuntimeAXNode] {
        runAXRead {
            guard let menuBar = cuAttribute(appElement, name: kAXMenuBarAttribute as String) as AXUIElement? else {
                return []
            }

            return flattenTree(
                from: menuBar,
                focusedElement: focusedElement,
                visibleFrame: cuFrame(menuBar) ?? fallbackFrame,
                filterVisibleNodes: filterVisibleNodes,
                maxDepth: 1
            )
        }
    }

    private static func statusMenuExtraNodes(
        statusMenuExtras: [AXUIElement],
        focusedElement: AXUIElement?,
        fallbackFrame: CGRect,
        filterVisibleNodes: Bool
    ) -> [RuntimeAXNode] {
        runAXRead {
            var nodes: [RuntimeAXNode] = []
            for statusItem in statusMenuExtras {
                nodes.append(contentsOf: reindexedNodes(
                    flattenTree(
                        from: statusItem,
                        focusedElement: focusedElement,
                        visibleFrame: cuFrame(statusItem) ?? fallbackFrame,
                        filterVisibleNodes: filterVisibleNodes,
                        maxDepth: 0
                    ),
                    startingAt: nodes.count
                ))
            }
            return nodes
        }
    }

    static func reindexedNodes(
        _ nodes: [RuntimeAXNode],
        startingAt offset: Int
    ) -> [RuntimeAXNode] {
        nodes.map { node in
            RuntimeAXNode(
                index: node.index + offset,
                depth: node.depth,
                element: node.element,
                role: node.role,
                subrole: node.subrole,
                title: node.title,
                description: node.description,
                value: node.value,
                help: node.help,
                identifier: node.identifier,
                url: node.url,
                enabled: node.enabled,
                selected: node.selected,
                expanded: node.expanded,
                focused: node.focused,
                frame: node.frame,
                actions: node.actions,
                isValueSettable: node.isValueSettable,
                valueTypeDescription: node.valueTypeDescription,
                collectionSummary: node.collectionSummary
            )
        }
    }

    static func flattenTree(
        from root: AXUIElement,
        focusedElement: AXUIElement?,
        visibleFrame: CGRect,
        filterVisibleNodes: Bool,
        maxDepth: Int = 64
    ) -> [RuntimeAXNode] {
        struct PendingNode {
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
            let children: [PendingNode]
        }

        var visited = Set<CFHashCode>()

        func build(
            _ element: AXUIElement,
            depth: Int,
            visibleClip: CGRect,
            insideWebArea: Bool,
            insideVisibleRow: Bool
        ) -> PendingNode? {
            guard depth <= maxDepth else {
                return nil
            }

            let identifier = CFHash(element)
            if visited.contains(identifier) {
                return nil
            }
            visited.insert(identifier)

            // One batched AX round-trip for the per-node scalar attributes instead of ~14 separate
            // cross-process calls — this is the dominant capture cost on large trees (e.g. Mail).
            let attrs = cuMultipleAttributes(element, [
                kAXRoleAttribute as String,
                kAXSubroleAttribute as String,
                kAXTitleAttribute as String,
                kAXDescriptionAttribute as String,
                kAXIdentifierAttribute as String,
                kAXURLAttribute as String,
                kAXEnabledAttribute as String,
                kAXSelectedAttribute as String,
                kAXExpandedAttribute as String,
                "AXDisclosing",
                kAXPositionAttribute as String,
                kAXSizeAttribute as String,
                "AXHidden",
            ])
            let role = (attrs[kAXRoleAttribute as String] as? String) ?? "AXUnknown"
            let subrole = (attrs[kAXSubroleAttribute as String] as? String) ?? ""
            let title = (attrs[kAXTitleAttribute as String] as? String) ?? ""
            let description = (attrs[kAXDescriptionAttribute as String] as? String) ?? ""
            let frame = cuFrame(position: attrs[kAXPositionAttribute as String], size: attrs[kAXSizeAttribute as String])
            let focused = focusedElement.map { CFEqual($0, element) }
            let selected = attrs[kAXSelectedAttribute as String] as? Bool
            let hidden = (attrs["AXHidden"] as? Bool) == true
            if hidden, depth > 0, focused != true, selected != true {
                return nil
            }

            let rawChildren = cuChildElementsForWalk(element, role: role)
            let collectionSummary = cuCollectionSummary(element, role: role)
            let childVisibleClip = filterVisibleNodes
                ? cuDescendantVisibleClip(role: role, frame: frame, inheritedClip: visibleClip)
                : visibleClip
            let childInsideWebArea = insideWebArea || role == "AXWebArea"
            // Once inside an on-screen table/outline row, keep its text descendants even if an
            // individual cell/label frame fails the per-leaf visibility threshold — this matches the
            // reference (Codex), which keeps the content of visible rows. Bounded to visible rows, and
            // the subtree is walked either way, so this only affects output completeness, not speed.
            let childInsideVisibleRow = insideVisibleRow ||
                (role == "AXRow" && cuFrameIsVisible(frame, in: visibleClip))
            let children = rawChildren.compactMap {
                build(
                    $0,
                    depth: depth + 1,
                    visibleClip: childVisibleClip,
                    insideWebArea: childInsideWebArea,
                    insideVisibleRow: childInsideVisibleRow
                )
            }

            let frameVisible = insideWebArea
                ? cuWebFrameIsMeaningfullyVisible(frame, in: visibleClip)
                : cuFrameIsVisible(frame, in: visibleClip)
            let visible = if roleCanContainVisibleDescendants(role) {
                frameVisible || children.isEmpty == false
            } else {
                insideWebArea
                    ? cuWebFrameIsMeaningfullyVisible(frame, in: visibleClip)
                    : cuFrameIsMeaningfullyVisible(frame, in: visibleClip)
            }
            let selfDescribingStructuralNode = roleCanContainVisibleDescendants(role) &&
                (!title.isEmpty || !description.isEmpty)
            if filterVisibleNodes,
               depth > 0,
               !visible,
               !insideVisibleRow,
               !selfDescribingStructuralNode,
               focused != true,
               selected != true
            {
                return nil
            }

            let value = shouldFetchFullValue(for: role)
                ? cuRawAttribute(element, name: kAXValueAttribute as String)
                : nil
            let help = shouldFetchHelp(for: role, title: title, description: description, value: value)
                ? (cuAttribute(element, name: kAXHelpAttribute as String) as String? ?? "")
                : ""
            return PendingNode(
                element: element,
                role: role,
                subrole: subrole,
                title: title,
                description: description,
                value: value,
                help: help,
                identifier: (attrs[kAXIdentifierAttribute as String] as? String) ?? "",
                url: attrs[kAXURLAttribute as String] as? URL,
                enabled: attrs[kAXEnabledAttribute as String] as? Bool,
                selected: selected,
                expanded: (attrs[kAXExpandedAttribute as String] as? Bool) ?? (attrs["AXDisclosing"] as? Bool),
                focused: focused,
                frame: frame,
                actions: shouldFetchActions(for: role) ? cuActions(element) : [],
                isValueSettable: shouldFetchSettable(for: role) ? cuIsAttributeSettable(element, name: kAXValueAttribute as String) : false,
                valueTypeDescription: describeValueType(value),
                collectionSummary: collectionSummary,
                children: children
            )
        }

        guard let rootNode = build(root, depth: 0, visibleClip: visibleFrame, insideWebArea: false, insideVisibleRow: false) else {
            return []
        }

        var nodes: [RuntimeAXNode] = []
        func emit(_ pending: PendingNode, depth: Int) {
            let index = nodes.count
            nodes.append(RuntimeAXNode(
                index: index,
                depth: depth,
                element: pending.element,
                role: pending.role,
                subrole: pending.subrole,
                title: pending.title,
                description: pending.description,
                value: pending.value,
                help: pending.help,
                identifier: pending.identifier,
                url: pending.url,
                enabled: pending.enabled,
                selected: pending.selected,
                expanded: pending.expanded,
                focused: pending.focused,
                frame: pending.frame,
                actions: pending.actions,
                isValueSettable: pending.isValueSettable,
                valueTypeDescription: pending.valueTypeDescription,
                collectionSummary: pending.collectionSummary
            ))
            for child in pending.children {
                emit(child, depth: depth + 1)
            }
        }
        emit(rootNode, depth: 0)

        return nodes
    }

    static func fingerprint(
        app: NSRunningApplication,
        windowID: Int,
        windowTitle: String,
        windowFrame: CGRect,
        nodes: [RuntimeAXNode],
        focusedElementIndex: Int?,
        selectedText: String?
    ) -> String {
        let parts = nodes.map { node -> String in
            let components: [String] = [
                "\(node.index)",
                node.role,
                node.subrole,
                node.title,
                stableFingerprintValue(for: node),
                node.help,
                node.identifier,
                stableFingerprintURL(for: node),
                node.enabled.map(String.init) ?? "",
                node.selected.map(String.init) ?? "",
                node.expanded.map(String.init) ?? "",
                node.frame.map(stableRectString) ?? "",
                node.actions.joined(separator: ","),
            ]
            return components.joined(separator: "|")
        }

        let payload = """
        \(app.bundleIdentifier ?? "")
        |\(app.processIdentifier)
        |\(windowID)
        |\(windowTitle)
        |\(stableRectString(windowFrame))
        |focus=\(focusedElementIndex.map(String.init) ?? "")
        |selected=\(selectedText ?? "")
        |\(parts.joined(separator: "\n"))
        """

        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func shouldFetchActions(for role: String) -> Bool {
        actionRoles.contains(role)
    }

    private static func shouldFetchSettable(for role: String) -> Bool {
        valueRoles.contains(role)
    }

    private static func shouldFetchFullValue(for role: String) -> Bool {
        valueRoles.contains(role) || textRoles.contains(role)
    }

    private static func shouldFetchHelp(
        for role: String,
        title: String,
        description: String,
        value: Any?
    ) -> Bool {
        guard controlRoles.contains(role) else {
            return false
        }
        return title.isEmpty && description.isEmpty && stringValueOrNil(value)?.isEmpty != false
    }

    private static let actionRoles: Set<String> = [
        kAXButtonRole as String,
        kAXCheckBoxRole as String,
        "AXLink",
        kAXMenuButtonRole as String,
        kAXMenuItemRole as String,
        kAXPopUpButtonRole as String,
        kAXRadioButtonRole as String,
        kAXSliderRole as String,
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
    ]

    private static let valueRoles: Set<String> = [
        kAXCheckBoxRole as String,
        kAXComboBoxRole as String,
        kAXPopUpButtonRole as String,
        kAXRadioButtonRole as String,
        kAXSliderRole as String,
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
    ]

    private static let textRoles: Set<String> = [
        kAXStaticTextRole as String,
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
    ]

    private static let controlRoles: Set<String> = actionRoles.union(valueRoles)
}
