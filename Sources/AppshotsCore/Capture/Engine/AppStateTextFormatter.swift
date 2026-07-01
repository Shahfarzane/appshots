import ApplicationServices
import Foundation

enum AppStateTextFormatter {
    static func format(
        snapshot: RuntimeAppSnapshot,
        includeElementIndexes: Bool = true,
        preserveTextAreaNewlines: Bool = false
    ) -> String {
        let appName = snapshot.app.localizedName ?? snapshot.app.bundleIdentifier ?? "Unknown"
        let focusedLine = if let focusedIndex = snapshot.focusedElementIndex,
                             let focusedNode = try? snapshot.node(index: focusedIndex)
        {
            "\nThe focused UI element is \(focusedElementDescription(focusedNode, includeElementIndexes: includeElementIndexes, preserveTextAreaNewlines: preserveTextAreaNewlines))"
        } else {
            ""
        }

        let selectedTextLine = AXRenderPolicy.selectedTextBlock(snapshot.selectedText)

        let lines = presentationRows(
            for: snapshot.nodes,
            surface: snapshot.surfaceKind.rawValue,
            focusedIndex: snapshot.focusedElementIndex
        )
            .map {
                format(
                    node: $0.node,
                    displayDepth: $0.displayDepth,
                    includeElementIndexes: includeElementIndexes,
                    preserveTextAreaNewlines: preserveTextAreaNewlines
                )
            }
        return """
        App=\(snapshot.app.bundleIdentifier ?? appName) (pid \(snapshot.app.processIdentifier))
        Window: "\(snapshot.windowTitle)", App: \(appName).
        \(lines.joined(separator: "\n"))\(focusedLine)\(selectedTextLine)
        """
    }

    private struct PresentationRow {
        let node: RuntimeAXNode
        let displayDepth: Int
    }

    private static func presentationRows(
        for nodes: [RuntimeAXNode],
        surface: String,
        focusedIndex: Int?
    ) -> [PresentationRow] {
        var result: [PresentationRow] = []
        var visibleDepthBySourceDepth: [Int: Int] = [:]
        var lastVisibleAncestorBySourceDepth: [Int: RuntimeAXNode] = [:]
        let singleCellRowCellIndexes = singleCellRowCellIndexes(in: nodes)

        for node in nodes {
            for staleDepth in Array(visibleDepthBySourceDepth.keys) where staleDepth >= node.depth {
                visibleDepthBySourceDepth[staleDepth] = nil
                lastVisibleAncestorBySourceDepth[staleDepth] = nil
            }

            let visibleAncestorDepth = nearestVisibleAncestorDepth(
                forSourceDepth: node.depth,
                visibleDepthBySourceDepth: visibleDepthBySourceDepth
            )
            let parentVisibleDepth = visibleAncestorDepth.map { visibleDepthBySourceDepth[$0] ?? -1 } ?? -1
            let displayDepth = max(0, parentVisibleDepth + 1)
            let parent = visibleAncestorDepth.flatMap { lastVisibleAncestorBySourceDepth[$0] }

            if shouldPresent(
                node,
                surface: surface,
                focusedIndex: focusedIndex,
                visibleParent: parent,
                collapseSingleCell: singleCellRowCellIndexes.contains(node.index)
            ) {
                result.append(PresentationRow(node: node, displayDepth: displayDepth))
                visibleDepthBySourceDepth[node.depth] = displayDepth
                lastVisibleAncestorBySourceDepth[node.depth] = node
            }
        }

        return result
    }

    private static func nearestVisibleAncestorDepth(
        forSourceDepth sourceDepth: Int,
        visibleDepthBySourceDepth: [Int: Int]
    ) -> Int? {
        guard sourceDepth > 0 else { return nil }
        for depth in stride(from: sourceDepth - 1, through: 0, by: -1) {
            if visibleDepthBySourceDepth[depth] != nil {
                return depth
            }
        }
        return nil
    }

    private static func shouldPresent(
        _ node: RuntimeAXNode,
        surface: String,
        focusedIndex: Int?,
        visibleParent: RuntimeAXNode?,
        collapseSingleCell: Bool
    ) -> Bool {
        if isRedundantLeaf(node, visibleParent: visibleParent) {
            return false
        }
        return AXRenderPolicy.shouldRenderSelf(
            node,
            surface: surface,
            focusedIndex: focusedIndex,
            collapseSingleCell: collapseSingleCell
        )
    }

    private static func singleCellRowCellIndexes(in nodes: [RuntimeAXNode]) -> Set<Int> {
        var result = Set<Int>()
        for (position, node) in nodes.enumerated() where node.role == kAXRowRole as String {
            var directCellIndexes: [Int] = []
            var cursor = position + 1
            while cursor < nodes.count, nodes[cursor].depth > node.depth {
                let child = nodes[cursor]
                if child.depth == node.depth + 1,
                   child.role == kAXCellRole as String {
                    directCellIndexes.append(child.index)
                }
                cursor += 1
            }
            if directCellIndexes.count == 1,
               let index = directCellIndexes.first {
                result.insert(index)
            }
        }
        return result
    }

    private static func format(
        node: RuntimeAXNode,
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

    private static func focusedElementDescription(
        _ node: RuntimeAXNode,
        includeElementIndexes: Bool,
        preserveTextAreaNewlines: Bool
    ) -> String {
        format(
            node: node,
            displayDepth: 0,
            includeElementIndexes: includeElementIndexes,
            preserveTextAreaNewlines: preserveTextAreaNewlines
        )
    }

    private static func isRedundantLeaf(_ node: RuntimeAXNode, visibleParent: RuntimeAXNode?) -> Bool {
        guard let visibleParent,
              node.role == kAXStaticTextRole as String || node.role == kAXImageRole as String
        else {
            return false
        }

        let childLabel = AXRenderPolicy.normalizeDisplay(AXRenderPolicy.primaryLabel(for: node))
        guard childLabel.isEmpty == false else {
            return node.role == kAXImageRole as String
        }

        let parentLabel = AXRenderPolicy.normalizeDisplay(AXRenderPolicy.primaryLabel(for: visibleParent))
        return parentLabel == childLabel || parentLabel.contains(childLabel)
    }
}
