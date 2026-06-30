import SwiftUI

/// Semantic color tokens for Appshots, cohesive with Loop's palette (system
/// accent + SwiftUI semantic colors). Use these instead of inline `Color`
/// literals/opacities so surfaces stay consistent.
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
