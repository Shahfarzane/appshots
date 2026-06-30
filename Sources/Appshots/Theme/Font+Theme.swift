import SwiftUI

/// Typography tokens for Appshots, matching Loop's pure-semantic Dynamic Type
/// ramp: `.title2` (window header) > `.title3` (section/item titles) >
/// `.callout` (row text) > `.caption`/`.caption2` (footnotes), plus the one
/// literal `.system(size: 12, weight: .medium)` Luminare uses for sidebar tabs.
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
