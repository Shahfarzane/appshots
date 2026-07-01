import SwiftUI

/// Design tokens for Appshots, derived from the Loop / Luminare design system.
///
/// Loop defines almost no tokens of its own — it leans on Luminare's
/// environment-injected constants (corner radius, row height, form spacing,
/// animation) plus SwiftUI semantic fonts/colors. Appshots mirrors that: inside
/// Luminare views we accept Luminare's own metrics, and this namespace only
/// names the handful of values Luminare doesn't own (window/thumbnail geometry,
/// status semantics, the dark Preview palette, animation curves) so the
/// non-Luminare surfaces stay cohesive.
///
/// Color and Font tokens live in `Color+Theme.swift` / `Font+Theme.swift`.
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
        /// Matches Luminare's default control corner radius.
        static let control: CGFloat = 12
        static let panel: CGFloat = 14
    }

    /// Opacities used for fills and borders on non-Luminare surfaces.
    enum Opacity {
        static let surfaceSubtle: Double = 0.08
        static let warningSurface: Double = 0.12
        static let surfaceSelected: Double = 0.14
        static let borderSubtle: Double = 0.18
        static let borderSelected: Double = 0.5
    }

    /// Animation curves, mirroring Luminare's `luminareAnimation`/`…Fast`.
    enum Motion {
        static let standard: Animation = .smooth(duration: 0.2)
        static let fast: Animation = .easeInOut(duration: 0.1)
        static let toggle: Animation = .easeInOut(duration: 0.15)
        static let flourish: Animation = .smooth(duration: 0.5)
    }

    /// Window and element geometry.
    enum Size {
        static let sidebarWidth: CGFloat = 230
        static let paneWidth: CGFloat = 390
        static let historyPaneWidth: CGFloat = 540
        static let settingsHeight: CGFloat = 620
        static let popover = CGSize(width: 400, height: 620)
        static let tabIcon: CGFloat = 22
        static let statusDot: CGFloat = 10

        /// Recent-capture thumbnails in the popover.
        static let popoverThumbnail = CGSize(width: 52, height: 34)
        /// History row thumbnails.
        static let historyThumbnail = CGSize(width: 96, height: 64)
    }
}
