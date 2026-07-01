import Foundation

enum AXRolePresentation {
    static let primaryControlRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXTextField",
        "AXTextArea",
        "AXPopUpButton",
        "AXComboBox",
        "AXSlider",
        "AXIncrementor",
        "AXScrollBar",
        "AXLink",
        "AXMenuButton",
    ]

    static func isPrimaryControlRole(_ role: String) -> Bool {
        primaryControlRoles.contains(role)
    }

    static func isTextRole(_ role: String) -> Bool {
        role == "AXStaticText" || role == "AXHeading"
    }

    static func isImageRole(_ role: String) -> Bool {
        role == "AXImage"
    }

    static func isMenuRole(_ role: String) -> Bool {
        role == "AXMenuBar" ||
            role == "AXMenu" ||
            role == "AXMenuItem" ||
            role == "AXMenuBarItem"
    }

    static func isTableStructureRole(_ role: String) -> Bool {
        role == "AXRow" ||
            role == "AXCell" ||
            role == "AXColumn"
    }

    static func roleCanContainVisibleDescendants(_ role: String) -> Bool {
        [
            "AXApplication",
            "AXWindow",
            "AXGroup",
            "AXScrollArea",
            "AXList",
            "AXOutline",
            "AXTable",
            "AXRow",
            "AXColumn",
            "AXSplitGroup",
            "AXSplitter",
            "AXTabGroup",
            "AXToolbar",
            "AXWebArea",
            "AXGenericElement",
        ].contains(role)
    }

    static func displayLabel(role: String, subrole: String, title: String) -> String {
        switch role {
        case "AXWindow":
            return subrole == "AXStandardWindow" ? "standard window" : "window"
        case "AXGroup", "AXGenericElement":
            return "container"
        case "AXWebArea":
            return "HTML content"
        case "AXTabGroup":
            return "tab group"
        case "AXButton":
            return "button"
        case "AXPopUpButton":
            return "pop up button"
        case "AXComboBox":
            return "combo box"
        case "AXRadioButton":
            return subrole == "AXTabButton" ? "tab" : "radio button"
        case "AXCheckBox":
            return "toggle button"
        case "AXTextField":
            return "text field"
        case "AXTextArea":
            return "text area"
        case "AXStaticText":
            return "text"
        case "AXHeading":
            return "heading"
        case "AXImage":
            return "image"
        case "AXList":
            return subrole == "AXContentList" ? "content list" : "list"
        case "AXRow":
            return "row"
        case "AXCell":
            return "cell"
        case "AXColumn":
            return "column"
        case "AXToolbar":
            return "toolbar"
        case "AXMenuBar":
            return "menu bar"
        case "AXMenuBarItem":
            return title.isEmpty ? "menu bar item" : ""
        case "AXMenuItem":
            return title.isEmpty ? "menu item" : ""
        case "AXUnknown":
            return title.isEmpty ? "unknown" : ""
        default:
            return normalizedRoleName(role)
        }
    }

    private static func normalizedRoleName(_ role: String) -> String {
        var raw = role
        if raw.hasPrefix("AX") {
            raw.removeFirst(2)
        }
        guard raw.isEmpty == false else { return "" }
        return raw
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .lowercased()
    }
}
