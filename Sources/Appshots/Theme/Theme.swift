import SwiftUI

/// Design tokens for Appshots, derived from the Loop / Luminare design system.
///
/// Loop defines almost no tokens of its own — it leans on Luminare's
/// environment-injected constants (corner radius, row height, form spacing) plus
/// SwiftUI semantic fonts/colors. Appshots mirrors that: inside Luminare views we
/// accept Luminare's own metrics, and these tokens name only the handful of values
/// Luminare doesn't own (window/thumbnail geometry, status semantics) so the
/// non-Luminare surfaces stay cohesive.
enum AppshotsTheme {
    /// 4-pt spacing grid, matching Loop's `0, 1, 3, 4, 8, 12, 16` vocabulary.
    enum Spacing {
        static let hairline: CGFloat = 1
        static let xxs: CGFloat = 3
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        /// Matches Luminare's default form spacing between sections.
        static let section: CGFloat = 16
    }

    /// Corner radii. Inside Luminare views prefer Luminare's own metrics; these
    /// are for the popover / history / preview surfaces.
    enum Radius {
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 8
    }

    /// Opacities used for fills and borders on non-Luminare surfaces.
    enum Opacity {
        static let surfaceSubtle: Double = 0.08
        static let warningSurface: Double = 0.12
        static let surfaceSelected: Double = 0.14
        static let borderSubtle: Double = 0.18
        static let borderSelected: Double = 0.5
    }

    /// Window and element geometry.
    enum Size {
        static let sidebarWidth: CGFloat = 230
        static let paneWidth: CGFloat = 390
        static let settingsHeight: CGFloat = 420
        static let popover = CGSize(width: 400, height: 620)
        static let tabIcon: CGFloat = 22
        static let statusDot: CGFloat = 10

        /// Recent-capture thumbnails in the popover.
        static let popoverThumbnail = CGSize(width: 52, height: 34)
    }
}

/// Semantic color tokens, cohesive with Loop's palette (system accent + SwiftUI
/// semantic colors). Use these instead of inline `Color` literals/opacities.
extension Color {
    // MARK: Status
    static let appSuccess = Color.green
    static let appWarning = Color.orange
    static let appDestructive = Color.red
    /// Inactive status indicator (e.g. MCP "not enabled").
    static let appStatusInactive = Color.gray

    // MARK: Surfaces (on the standard light/dark window)
    /// Subtle card fill.
    static let appSurfaceSubtle = Color.secondary.opacity(AppshotsTheme.Opacity.surfaceSubtle)
    /// Selected row/card fill.
    static let appSurfaceSelected = Color.accentColor.opacity(AppshotsTheme.Opacity.surfaceSelected)
    /// Warning notice background.
    static let appWarningSurface = Color.orange.opacity(AppshotsTheme.Opacity.warningSurface)
    /// Hairline border for cards.
    static let appBorderSubtle = Color.secondary.opacity(AppshotsTheme.Opacity.borderSubtle)
    /// Hairline border for selected cards.
    static let appBorderSelected = Color.accentColor.opacity(AppshotsTheme.Opacity.borderSelected)
}

/// Typography tokens, matching Loop's pure-semantic Dynamic Type ramp:
/// `.title2` (window header) > `.callout` (row text) > `.caption`/`.caption2`.
extension Font {
    /// Pane / window header title.
    static let appWindowTitle: Font = .title2
    /// Standard row label / control text.
    static let appRowLabel: Font = .callout
    /// Card / setting title.
    static let appCardTitle: Font = .callout.weight(.medium)
    /// Secondary / footnote text.
    static let appCaption: Font = .caption
    /// Timestamps / fine print.
    static let appCaptionSmall: Font = .caption2
}
