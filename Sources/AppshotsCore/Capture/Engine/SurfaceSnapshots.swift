import AppKit
import ApplicationServices
import Foundation

extension AccessibilityCaptureEngine {
    static func menuSurfaceSnapshot(
        app: NSRunningApplication,
        appElement: AXUIElement,
        windowMatch: ResolvedWindowMatch,
        focusedElement: AXUIElement?,
        selectedText: String?,
        statusMenuExtras: [AXUIElement],
        transientMenuWindowFrame: CGRect?,
        filterVisibleNodes: Bool
    ) -> RuntimeAppSnapshot? {
        runAXRead {
            if let menuWindowFrame = transientMenuWindowFrame {
                let roots = [appElement, windowMatch.element] + cuElements(from: focusedElement)
                if let popupMenu = popupMenuCandidate(
                    near: roots,
                    requireVisibleItems: false,
                    matching: menuWindowFrame
                ) {
                    return menuSurfaceSnapshot(
                        app: app,
                        windowMatch: windowMatch,
                        focusedElement: focusedElement,
                        selectedText: selectedText,
                        popupMenu: PopupMenuCandidate(element: popupMenu.element, frame: menuWindowFrame),
                        filterVisibleNodes: false
                    )
                }
            }

            if let popupMenu = activeMenuBarItemCandidate(in: appElement) ??
                activeStatusMenuItemCandidate(in: statusMenuExtras) {
                return menuSurfaceSnapshot(
                    app: app,
                    windowMatch: windowMatch,
                    focusedElement: focusedElement,
                    selectedText: selectedText,
                    popupMenu: popupMenu,
                    filterVisibleNodes: filterVisibleNodes
                )
            }
            return nil
        }
    }

    private static func menuSurfaceSnapshot(
        app: NSRunningApplication,
        windowMatch: ResolvedWindowMatch,
        focusedElement: AXUIElement?,
        selectedText: String?,
        popupMenu: PopupMenuCandidate,
        filterVisibleNodes: Bool
    ) -> RuntimeAppSnapshot? {
            let nodes = flattenTree(
                from: popupMenu.element,
                focusedElement: focusedElement,
                visibleFrame: popupMenu.frame,
                filterVisibleNodes: filterVisibleNodes
            )
            let focusedIndex = focusedElement.flatMap { focused in
                nodes.first(where: { CFEqual($0.element, focused) })?.index
            }
            let fingerprint = fingerprint(
                app: app,
                windowID: windowMatch.cgWindow.windowID,
                windowTitle: windowMatch.title,
                windowFrame: windowMatch.frame,
                nodes: nodes,
                focusedElementIndex: focusedIndex,
                selectedText: selectedText
            )

            return RuntimeAppSnapshot(
                app: app,
                surfaceKind: .menu,
                windowID: windowMatch.cgWindow.windowID,
                windowTitle: windowMatch.title,
                windowFrame: windowMatch.frame,
                nodes: nodes,
                focusedElementIndex: focusedIndex,
                selectedText: selectedText,
                screenshotURL: nil,
                screenshotSize: nil,
                fingerprint: fingerprint
            )
    }

    static func statusSurfaceSnapshot(
        app: NSRunningApplication,
        appElement: AXUIElement,
        focusedElement: AXUIElement?,
        selectedText: String?,
        statusMenuExtras: [AXUIElement],
        filterVisibleNodes: Bool
    ) -> RuntimeAppSnapshot? {
        if let popupMenu = activeStatusMenuItemCandidate(in: statusMenuExtras) {
            return statusSurfaceSnapshot(
                app: app,
                appElement: appElement,
                focusedElement: focusedElement,
                selectedText: selectedText,
                rootElement: popupMenu.element,
                surfaceKind: .menu,
                title: "Status Menu",
                frame: popupMenu.frame,
                filterVisibleNodes: filterVisibleNodes
            )
        }

        let statusItems = statusMenuExtras
        guard let firstStatusItem = statusItems.first else {
            return nil
        }

        let frames = statusItems.compactMap(cuFrame)
        let frame = frames.reduce(CGRect.null) { partial, next in
            partial.isNull ? next : partial.union(next)
        }
        let visibleFrame = frame.isNull ? (cuFrame(firstStatusItem) ?? .zero) : frame

        var nodes: [RuntimeAXNode] = []
        for statusItem in statusItems {
            nodes.append(contentsOf: reindexedNodes(
                flattenTree(
                    from: statusItem,
                    focusedElement: focusedElement,
                    visibleFrame: cuFrame(statusItem) ?? visibleFrame,
                    filterVisibleNodes: filterVisibleNodes,
                    maxDepth: 0
                ),
                startingAt: nodes.count
            ))
        }

        return statusSurfaceSnapshot(
            app: app,
            appElement: appElement,
            focusedElement: focusedElement,
            selectedText: selectedText,
            rootElement: firstStatusItem,
            surfaceKind: .status,
            title: "Status Items",
            frame: visibleFrame,
            nodes: nodes,
            filterVisibleNodes: filterVisibleNodes
        )
    }

    private static func statusSurfaceSnapshot(
        app: NSRunningApplication,
        appElement: AXUIElement,
        focusedElement: AXUIElement?,
        selectedText: String?,
        rootElement: AXUIElement,
        surfaceKind: RuntimeSurfaceKind,
        title: String,
        frame: CGRect,
        nodes providedNodes: [RuntimeAXNode]? = nil,
        filterVisibleNodes: Bool
    ) -> RuntimeAppSnapshot {
        let nodes = providedNodes ?? flattenTree(
            from: rootElement,
            focusedElement: focusedElement,
            visibleFrame: frame,
            filterVisibleNodes: filterVisibleNodes
        )
        let focusedIndex = focusedElement.flatMap { focused in
            nodes.first(where: { CFEqual($0.element, focused) })?.index
        }
        let windowID = statusSurfaceWindowID(app: app, frame: frame)
        let fingerprint = fingerprint(
            app: app,
            windowID: windowID,
            windowTitle: title,
            windowFrame: frame,
            nodes: nodes,
            focusedElementIndex: focusedIndex,
            selectedText: selectedText
        )

        return RuntimeAppSnapshot(
            app: app,
            surfaceKind: surfaceKind,
            windowID: windowID,
            windowTitle: title,
            windowFrame: frame,
            nodes: nodes,
            focusedElementIndex: focusedIndex,
            selectedText: selectedText,
            screenshotURL: nil,
            screenshotSize: nil,
            fingerprint: fingerprint
        )
    }

    private static func statusSurfaceWindowID(app _: NSRunningApplication, frame _: CGRect) -> Int {
        return 0
    }
}
