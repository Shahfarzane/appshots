import CoreGraphics
import Foundation

/// Layout + appearance constants for the polished "transition snapshot" — the
/// rounded screenshot card with a bottom fade, a centered app icon overlapping
/// the card's lower edge, and a centered app title.
///
/// The same numbers drive two consumers: the offscreen PNG renderer
/// (`AppshotTransitionSnapshotRenderer`) that persists `transition-snapshot.png`
/// beside the capture, and the live capture-flight overlay in the menu-bar app.
/// Keeping them in one `Sendable` value keeps the rendered asset and the
/// on-screen composition in lockstep.
///
/// All values are in points and assume a TOP-LEFT origin (y grows downward).
public struct AppshotTransitionSnapshotStyle: Sendable, Equatable {
    /// Full canvas width in points (card + shadow gutters). Stays constant.
    public var displayWidth: CGFloat
    /// Inset from the canvas edge to the card, leaving room for the shadow.
    public var horizontalPadding: CGFloat
    /// Inset from the canvas top to the card, leaving room for the shadow.
    public var topPadding: CGFloat
    /// Corner radius of the rounded screenshot card.
    public var screenshotCornerRadius: CGFloat
    /// Blur radius of the card's drop shadow.
    public var shadowRadius: CGFloat
    /// Downward offset of the card's drop shadow.
    public var shadowYOffset: CGFloat
    /// Opacity of the card's drop shadow.
    public var shadowOpacity: CGFloat
    /// Width and height of the centered app icon.
    public var iconSize: CGFloat
    /// How far the icon overlaps the card's lower edge.
    public var iconOverlap: CGFloat
    /// Gap from the icon's bottom to the title box.
    public var titleTopPadding: CGFloat
    /// Point size of the centered title.
    public var titleFontSize: CGFloat
    /// Padding below the title down to the canvas bottom.
    public var bottomPadding: CGFloat
    /// Fraction of the card height where the bottom fade begins.
    public var gradientStartFraction: CGFloat
    /// Fraction of the card height where the bottom fade ends.
    public var gradientEndFraction: CGFloat
    /// Maximum dim alpha applied at the card bottom.
    public var gradientDimOpacity: CGFloat
    /// Render scale used when no display scale is supplied.
    public var defaultBackingScale: CGFloat

    public init(
        displayWidth: CGFloat = 232,
        horizontalPadding: CGFloat = 16,
        topPadding: CGFloat = 16,
        screenshotCornerRadius: CGFloat = 14,
        shadowRadius: CGFloat = 18,
        shadowYOffset: CGFloat = 8,
        shadowOpacity: CGFloat = 0.28,
        iconSize: CGFloat = 40,
        iconOverlap: CGFloat = 14,
        titleTopPadding: CGFloat = 10,
        titleFontSize: CGFloat = 17,
        bottomPadding: CGFloat = 12,
        gradientStartFraction: CGFloat = 0.55,
        gradientEndFraction: CGFloat = 1.0,
        gradientDimOpacity: CGFloat = 0.55,
        defaultBackingScale: CGFloat = 2.0
    ) {
        self.displayWidth = displayWidth
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.screenshotCornerRadius = screenshotCornerRadius
        self.shadowRadius = shadowRadius
        self.shadowYOffset = shadowYOffset
        self.shadowOpacity = shadowOpacity
        self.iconSize = iconSize
        self.iconOverlap = iconOverlap
        self.titleTopPadding = titleTopPadding
        self.titleFontSize = titleFontSize
        self.bottomPadding = bottomPadding
        self.gradientStartFraction = gradientStartFraction
        self.gradientEndFraction = gradientEndFraction
        self.gradientDimOpacity = gradientDimOpacity
        self.defaultBackingScale = defaultBackingScale
    }

    /// The default Codex-style transition snapshot layout.
    public static let `default` = AppshotTransitionSnapshotStyle()

    /// Resolved geometry for the transition snapshot, in POINTS, top-left origin.
    /// Shared by the renderer, the live overlay, and tests so the layout math
    /// lives in exactly one place.
    public struct Layout: Sendable, Equatable {
        /// Full canvas size in points (`displayWidth` x computed height).
        public var canvasSize: CGSize
        /// The rounded screenshot card.
        public var cardRect: CGRect
        /// The app icon, centered and overlapping the card's lower edge.
        public var iconRect: CGRect
        /// The single centered title line's bounding box.
        public var titleBoxRect: CGRect

        public init(canvasSize: CGSize, cardRect: CGRect, iconRect: CGRect, titleBoxRect: CGRect) {
            self.canvasSize = canvasSize
            self.cardRect = cardRect
            self.iconRect = iconRect
            self.titleBoxRect = titleBoxRect
        }
    }

    /// Computes the transition snapshot layout for a screenshot of the given
    /// pixel size. The card height tracks the screenshot's aspect ratio so the
    /// image fills the card exactly.
    public func layout(forScreenshotPixelSize pixelSize: CGSize) -> Layout {
        let cardWidth = displayWidth - 2 * horizontalPadding
        let aspect: CGFloat = pixelSize.width > 0 ? pixelSize.height / pixelSize.width : 1
        let cardHeight = (cardWidth * aspect).rounded()

        let cardRect = CGRect(x: horizontalPadding, y: topPadding, width: cardWidth, height: cardHeight)

        let iconTop = topPadding + cardHeight - iconOverlap
        let iconRect = CGRect(
            x: displayWidth / 2 - iconSize / 2,
            y: iconTop,
            width: iconSize,
            height: iconSize
        )

        let titleBoxTop = iconTop + iconSize + titleTopPadding
        let titleHeight = (titleFontSize * 1.3).rounded(.up)
        let titleBoxRect = CGRect(
            x: horizontalPadding,
            y: titleBoxTop,
            width: cardWidth,
            height: titleHeight
        )

        let canvasHeight = titleBoxTop + titleHeight + bottomPadding

        return Layout(
            canvasSize: CGSize(width: displayWidth, height: canvasHeight),
            cardRect: cardRect,
            iconRect: iconRect,
            titleBoxRect: titleBoxRect
        )
    }
}
