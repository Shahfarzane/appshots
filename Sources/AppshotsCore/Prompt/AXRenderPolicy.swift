import Foundation

protocol AXRenderableNode {
    var index: Int { get }
    var depth: Int { get }
    var role: String { get }
    var subrole: String { get }
    var title: String { get }
    var description: String { get }
    var valueText: String? { get }
    var help: String { get }
    var identifier: String { get }
    var urlText: String? { get }
    var enabled: Bool? { get }
    var selected: Bool? { get }
    var expanded: Bool? { get }
    var focused: Bool? { get }
    var isValueSettable: Bool { get }
    var valueTypeDescription: String? { get }
    var collectionSummary: String? { get }
}

enum AXRenderPolicy {
    static let primaryLabelLimit = 4_000
    static let detailValueLimit = 4_000
    static let selectedTextLimit = 2_000

    static func selectedTextBlock(_ selectedText: String?) -> String {
        guard let selectedText, selectedText.isEmpty == false else {
            return ""
        }

        return """

        Selected text: ```
        \(truncate(selectedText, limit: selectedTextLimit))
        ```
        """
    }

    static func shouldRenderSelf<N: AXRenderableNode>(
        _ node: N,
        surface: String,
        focusedIndex: Int? = nil,
        collapseSingleCell: Bool = false
    ) -> Bool {
        if node.depth == 0 ||
            node.index == focusedIndex ||
            node.focused == true ||
            node.selected == true ||
            node.isValueSettable {
            return true
        }

        if collapseSingleCell {
            return false
        }

        if AXRolePresentation.isMenuRole(node.role) {
            return surface == "menu"
        }

        if AXRolePresentation.isTableStructureRole(node.role) {
            return true
        }

        if AXRolePresentation.isPrimaryControlRole(node.role) {
            return hasDisplaySignal(node) || node.enabled != false
        }

        if AXRolePresentation.isTextRole(node.role) {
            return hasDisplaySignal(node)
        }

        if AXRolePresentation.isImageRole(node.role) {
            return hasStrongDisplaySignal(node)
        }

        if AXRolePresentation.roleCanContainVisibleDescendants(node.role) {
            return hasStrongDisplaySignal(node)
        }

        return hasDisplaySignal(node) || node.enabled == false || node.expanded != nil
    }

    static func format<N: AXRenderableNode>(
        node: N,
        displayDepth: Int,
        includeElementIndexes: Bool,
        preserveTextAreaNewlines: Bool
    ) -> String {
        let indent = String(repeating: "\t", count: displayDepth)
        let stateDescription = describeStates(node)
        let primary = primaryLabel(for: node)
        let suffixParts = describeDetails(
            node,
            primaryLabel: primary,
            preserveTextAreaNewlines: preserveTextAreaNewlines
        )
        let suffixSeparator = suffixParts.first?.hasPrefix("URL:") == true ? ", " : " "
        let suffix = suffixParts.isEmpty ? "" : suffixSeparator + suffixParts.joined(separator: ", ")
        let label = displayLabel(for: node)
        let labelPart = [label, primary].filter { !$0.isEmpty }.joined(separator: " ")
        let prefix = includeElementIndexes ? "\(node.index)" : ""
        let head = [prefix, labelPart].filter { !$0.isEmpty }.joined(separator: " ")
        return "\(indent)\(head)\(stateDescription)\(suffix)"
    }

    static func primaryLabel<N: AXRenderableNode>(for node: N) -> String {
        if node.role == "AXMenuItem" || node.role == "AXMenuBarItem" {
            return normalizeDisplay(node.title)
        }

        var candidates = [
            node.title,
            node.description,
            node.help,
            node.valueText ?? "",
            meaningfulIdentifier(node.identifier) ?? "",
        ]
        if node.role == "AXTextArea" {
            candidates = [
                node.title,
                node.help,
                meaningfulIdentifier(node.identifier) ?? "",
            ]
        }

        let primary = candidates
            .map { truncate(normalizeDisplay($0), limit: primaryLabelLimit) }
            .first { !$0.isEmpty } ?? ""

        guard let collectionSummary = node.collectionSummary else {
            return primary
        }
        if primary.isEmpty {
            return "(\(collectionSummary))"
        }
        return "\(primary) (\(collectionSummary))"
    }

    static func describeStates<N: AXRenderableNode>(_ node: N) -> String {
        var states: [String] = []

        if node.enabled == false {
            states.append("disabled")
        }
        if node.selected == true {
            states.append("selected")
        }
        if node.expanded == true {
            states.append("expanded")
        } else if node.expanded == false {
            states.append("collapsed")
        }
        if node.isValueSettable {
            states.append("settable")
        }
        if let valueTypeDescription = node.valueTypeDescription, node.isValueSettable {
            states.append(valueTypeDescription)
        }

        guard states.isEmpty == false else {
            return ""
        }
        return " (\(states.joined(separator: ", ")))"
    }

    static func describeDetails<N: AXRenderableNode>(
        _ node: N,
        primaryLabel: String,
        preserveTextAreaNewlines: Bool
    ) -> [String] {
        var details: [String] = []

        if node.title.isEmpty == false,
           node.role != "AXMenuBarItem",
           node.role != "AXMenuItem",
           !primaryLabelContains(node.title, primaryLabel: primaryLabel)
        {
            details.append(truncate(normalizeDisplay(node.title), limit: detailValueLimit))
        }

        if node.description.isEmpty == false,
           node.description != node.title,
           !primaryLabelContains(node.description, primaryLabel: primaryLabel)
        {
            details.append("Description: \(truncate(normalizeDisplay(node.description), limit: detailValueLimit))")
        }

        if let identifier = meaningfulIdentifier(node.identifier),
           !primaryLabelContains(identifier, primaryLabel: primaryLabel) {
            details.append("ID: \(truncate(identifier, limit: detailValueLimit))")
        }

        if node.help.isEmpty == false,
           !primaryLabelContains(node.help, primaryLabel: primaryLabel) {
            details.append("Help: \(truncate(normalizeDisplay(node.help), limit: detailValueLimit))")
        }

        if let url = normalizedURL(node.urlText) {
            details.append("URL: \(truncate(url, limit: detailValueLimit))")
        }

        if let rawValue = node.valueText {
            let valueString = normalizeDisplay(rawValue)
            if valueString.isEmpty == false,
               valueString != node.title,
               !primaryLabelContains(valueString, primaryLabel: primaryLabel)
            {
                let value = displayValue(
                    rawValue,
                    preservingNewlines: preserveTextAreaNewlines && node.role == "AXTextArea"
                )
                details.append("Value: \(truncate(value, limit: detailValueLimit))")
            }
        }

        return details
    }

    static func displayLabel<N: AXRenderableNode>(for node: N) -> String {
        AXRolePresentation.displayLabel(role: node.role, subrole: node.subrole, title: node.title)
    }

    static func hasDisplaySignal<N: AXRenderableNode>(_ node: N) -> Bool {
        primaryLabel(for: node).isEmpty == false ||
            describeDetails(node, primaryLabel: "", preserveTextAreaNewlines: false).isEmpty == false ||
            node.enabled == false ||
            node.expanded != nil
    }

    static func hasStrongDisplaySignal<N: AXRenderableNode>(_ node: N) -> Bool {
        primaryLabel(for: node).isEmpty == false ||
            normalizedURL(node.urlText) != nil ||
            meaningfulIdentifier(node.identifier) != nil ||
            node.help.isEmpty == false ||
            node.enabled == false ||
            node.expanded != nil ||
            node.collectionSummary != nil
    }

    static func normalizeDisplay(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func displayValue(_ value: String, preservingNewlines: Bool) -> String {
        if preservingNewlines {
            return value
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalizeDisplay(value)
    }

    static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        let omitted = value.count - limit
        let prefixLength = max(0, limit - 24)
        let prefix = value.prefix(prefixLength)
        return "\(prefix)... [truncated \(omitted) chars]"
    }

    static func meaningfulIdentifier(_ identifier: String) -> String? {
        let value = normalizeDisplay(identifier)
        guard !value.isEmpty,
              !value.hasPrefix("_NS:"),
              !value.hasPrefix("AutomaticTableColumnIdentifier.") else {
            return nil
        }
        return value
    }

    static func primaryLabelContains(_ value: String, primaryLabel: String) -> Bool {
        let normalizedValue = normalizeDisplay(value)
        guard !normalizedValue.isEmpty else { return true }
        return normalizeDisplay(primaryLabel).contains(normalizedValue)
    }

    static func normalizedURL(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false
        else {
            return nil
        }
        if let url = URL(string: value),
           url.scheme == "https" || url.scheme == "http" || url.scheme == "file" {
            if url.scheme == "https" || url.scheme == "http" {
                var display = value
                if display.hasPrefix("https://www.") {
                    display.removeFirst("https://www.".count)
                } else if display.hasPrefix("https://") {
                    display.removeFirst("https://".count)
                } else if display.hasPrefix("http://") {
                    display.removeFirst("http://".count)
                }
                return display
            }
            return value
        }
        return value
    }
}

extension AXNode: AXRenderableNode {
    var valueText: String? { value }
    var urlText: String? { url }
}

extension RuntimeAXNode: AXRenderableNode {
    var valueText: String? { stringValueOrNil(value) }
    var urlText: String? { url?.absoluteString }
}
