import Foundation

enum AppshotSnapshotRenderer {
    static func render(
        state: CapturedAppState,
        includeElementIndexes: Bool = false,
        preserveTextAreaNewlines: Bool = true
    ) -> String {
        let metadata = state.metadata
        let rows = renderedRows(for: state.nodes, surface: state.surface)
            .map {
                format(
                    node: $0.node,
                    displayDepth: $0.displayDepth,
                    includeElementIndexes: includeElementIndexes,
                    preserveTextAreaNewlines: preserveTextAreaNewlines
                )
            }

        let focusedLine = state.focusedElementIndex.flatMap { focusedIndex in
            state.nodes.first(where: { $0.index == focusedIndex })
        }.map { focusedNode in
            "\nThe focused UI element is \(format(node: focusedNode, displayDepth: 0, includeElementIndexes: includeElementIndexes, preserveTextAreaNewlines: preserveTextAreaNewlines))"
        } ?? ""

        let selectedTextLine = selectedTextBlock(state.selectedText)
        let selectedNodeLine = selectedNodeBlock(
            state.nodes,
            includeElementIndexes: includeElementIndexes,
            preserveTextAreaNewlines: preserveTextAreaNewlines
        )

        return """
        <app_state surface="\(state.surface)">
        \(surfaceHint(for: state.surface))
        App=\(metadata.bundleID.isEmpty ? metadata.appName : metadata.bundleID) (pid \(metadata.pid))
        Window: "\(metadata.windowTitle)", App: \(metadata.appName).
        \(rows.joined(separator: "\n"))\(focusedLine)\(selectedNodeLine)\(selectedTextLine)
        </app_state>
        """
    }

    private struct RenderedRow {
        let node: AXNode
        let displayDepth: Int
    }

    private static func renderedRows(for nodes: [AXNode], surface: String) -> [RenderedRow] {
        guard nodes.isEmpty == false else { return [] }

        // Keyed tolerantly: `accessibility_tree.json` is re-decoded from disk
        // (documented external layout), so a duplicate node index in a
        // hand-edited or partially written file must degrade, not trap.
        let byIndex = Dictionary(nodes.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        let childrenByParent = Dictionary(grouping: nodes, by: \.parentIndex)
        let roots = nodes.filter { node in
            guard let parentIndex = node.parentIndex else { return true }
            return byIndex[parentIndex] == nil
        }

        var memo: [Int: Bool] = [:]
        func shouldRenderSubtree(_ node: AXNode) -> Bool {
            if let cached = memo[node.index] {
                return cached
            }

            let children = childrenByParent[node.index] ?? []
            let result = shouldRenderSelf(node, surface: surface) || children.contains { shouldRenderSubtree($0) }
            memo[node.index] = result
            return result
        }

        var result: [RenderedRow] = []
        func emit(_ node: AXNode, displayDepth: Int) {
            guard shouldRenderSubtree(node) else { return }

            let rendersSelf = shouldRenderSelf(node, surface: surface) || node.parentIndex == nil
            let nextDepth: Int
            if rendersSelf {
                result.append(RenderedRow(node: node, displayDepth: displayDepth))
                nextDepth = displayDepth + 1
            } else {
                nextDepth = displayDepth
            }

            for child in childrenByParent[node.index] ?? [] {
                emit(child, displayDepth: nextDepth)
            }
        }

        for root in roots {
            emit(root, displayDepth: 0)
        }

        return result
    }

    private static func shouldRenderSelf(_ node: AXNode, surface: String) -> Bool {
        AXRenderPolicy.shouldRenderSelf(node, surface: surface)
    }

    private static func format(
        node: AXNode,
        displayDepth: Int,
        includeElementIndexes: Bool,
        preserveTextAreaNewlines: Bool
    ) -> String {
        AXRenderPolicy.format(
            node: node,
            displayDepth: displayDepth,
            includeElementIndexes: includeElementIndexes,
            preserveTextAreaNewlines: preserveTextAreaNewlines
        )
    }

    private static func surfaceHint(for surface: String) -> String {
        switch surface {
        case "status":
            return "Surface: status. No app window is available; the state below contains the app's status item. Click it by element_index to open its status menu."
        case "menu":
            return "Surface: menu. An app menu is currently open. Click a menu item by element_index, or use press-key {\"key\":\"escape\"} to close the menu and return to the window."
        default:
            return "Surface: window. The state below is the app window."
        }
    }

    private static func selectedTextBlock(_ selectedText: String?) -> String {
        AXRenderPolicy.selectedTextBlock(selectedText)
    }

    private static func selectedNodeBlock(
        _ nodes: [AXNode],
        includeElementIndexes: Bool,
        preserveTextAreaNewlines: Bool
    ) -> String {
        let byIndex = Dictionary(nodes.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        let selectedNodes = nodes
            .filter { $0.selected == true && isSelectionSummaryRole($0.role) }
            .filter { node in
                var parentIndex = node.parentIndex
                while let currentParentIndex = parentIndex,
                      let parent = byIndex[currentParentIndex] {
                    if parent.selected == true && isSelectionSummaryRole(parent.role) {
                        return false
                    }
                    parentIndex = parent.parentIndex
                }
                return true
            }
            .prefix(3)

        guard selectedNodes.isEmpty == false else {
            return ""
        }

        let selectedLines = selectedNodes.map { node in
            format(
                node: node,
                displayDepth: 1,
                includeElementIndexes: includeElementIndexes,
                preserveTextAreaNewlines: preserveTextAreaNewlines
            )
        }.joined(separator: "\n")

        return """

        Selected:
        \(selectedLines)

        Note: Pay special attention to the content selected by the user. If the user asks a question or refers to the content they are looking at on-screen, they might be referring to the selected content (but they might be referring to something else that's visible, too).
        """
    }

    private static func isSelectionSummaryRole(_ role: String) -> Bool {
        role == "AXRow" ||
            role == "AXCell" ||
            role == "AXTable" ||
            role == "AXOutline"
    }
}
