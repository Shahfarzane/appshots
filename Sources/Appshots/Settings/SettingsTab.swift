import Luminare
import SwiftUI

/// The destinations in the Loop-style settings window sidebar, modeled on
/// Loop's `SettingsTab`. Conforms to Luminare's `LuminareTabItem` so it can
/// drive `LuminareSidebarSection`. Presented as a single "Appshots" group.
@MainActor
enum SettingsTab: String, CaseIterable, @MainActor LuminareTabItem {
    case general
    case mcp
    case history
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Settings"
        case .mcp: "MCP"
        case .history: "History"
        case .about: "About"
        }
    }

    /// SF Symbol for the sidebar tile (and the pane header).
    var image: Image {
        switch self {
        case .general: Image(systemName: "gearshape.fill")
        case .mcp: Image(systemName: "puzzlepiece.extension.fill")
        case .history: Image(systemName: "photo.on.rectangle.angled")
        case .about: Image(systemName: "info.circle.fill")
        }
    }

    /// Tile gradient color, mirroring Loop's per-tab accent tiles.
    var color: Color {
        switch self {
        case .general: Color(red: 0.44, green: 0.66, blue: 0.27)
        case .mcp: Color(red: 0.48, green: 0.47, blue: 0.66)
        case .history: Color(red: 0.81, green: 0.62, blue: 0.33)
        case .about: Color(red: 0.45, green: 0.45, blue: 0.45)
        }
    }

    var icon: some View {
        SettingsTabIconView(tab: self)
    }

    /// Shows the "update ready" dot on the About tab. The Luminare protocol
    /// requirement is `hasIndicator` (Loop's own `showIndicator` is a no-op).
    var hasIndicator: Bool {
        self == .about && AppshotsUpdateManager.shared.updateState == .installUpdate
    }

    @ViewBuilder
    func view() -> some View {
        switch self {
        case .general: GeneralSettingsView()
        case .mcp: MCPSettingsPane()
        case .history: HistorySettingsView()
        case .about: AboutSettingsView()
        }
    }

    /// Sidebar order under the single "Appshots" group.
    static let allTabs: [Self] = [.history, .general, .mcp, .about]
}

/// The 22×22 gradient rounded-rect sidebar tile with a centered white glyph,
/// copied from Loop's `SettingsTabIconView`.
struct SettingsTabIconView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tab: SettingsTab

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .foregroundStyle(tab.color.gradient)
            .opacity(0.8)
            .overlay {
                // Only add shine in dark mode; in light mode it makes the icon look fuzzy.
                if colorScheme == .dark, #available(macOS 26.0, *) {
                    borderShine(in: .rect(cornerRadius: 6))
                }

                tab.image
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1)
            }
            .frame(width: AppshotsTheme.Size.tabIcon, height: AppshotsTheme.Size.tabIcon)
    }

    /// Mimics macOS Tahoe's icon shine.
    private func borderShine(in shape: some InsettableShape) -> some View {
        shape
            .strokeBorder(.white, lineWidth: 1)
            .mask {
                LinearGradient(
                    colors: [.white, .clear, .white.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .opacity(0.4)
    }
}
