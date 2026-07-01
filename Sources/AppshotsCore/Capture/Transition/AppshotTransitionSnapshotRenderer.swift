import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Errors thrown while rendering a transition snapshot. Callers treat these as
/// best-effort: a failure means the capture simply has no transition PNG.
public enum AppshotTransitionSnapshotError: Error {
    case cannotCreateContext
    case unreadableScreenshot
    case encodeFailed
}

/// Pure, thread-safe renderer that draws the Codex-style transition snapshot
/// (rounded screenshot card + bottom fade + centered app icon overlapping the
/// card's lower edge + centered app title) into a PNG.
///
/// This deliberately uses only CoreGraphics / CoreText / ImageIO — no AppKit,
/// no main-thread APIs, no `NSImage`/`lockFocus`/`NSGraphicsContext` — so it can
/// run on the capture worker thread without touching the main actor. Drawing
/// happens in a TOP-LEFT origin coordinate system (the context's native
/// bottom-left space is flipped once up front) at the requested backing scale.
public enum AppshotTransitionSnapshotRenderer {
    public struct Request: Sendable {
        public var screenshot: CGImage
        /// App display name drawn as the centered title. Empty omits the title.
        public var appName: String
        /// App icon drawn over the card's lower edge. `nil` omits the icon layer.
        public var appIcon: CGImage?
        /// Render scale. Pixel size = canvas size in points * this scale.
        public var backingScale: CGFloat
        public var style: AppshotTransitionSnapshotStyle
        /// Title color. Defaults to an opaque near-black.
        public var titleColor: CGColor

        public init(
            screenshot: CGImage,
            appName: String,
            appIcon: CGImage? = nil,
            backingScale: CGFloat = AppshotTransitionSnapshotStyle.default.defaultBackingScale,
            style: AppshotTransitionSnapshotStyle = .default,
            titleColor: CGColor = CGColor(gray: 0.12, alpha: 1)
        ) {
            self.screenshot = screenshot
            self.appName = appName
            self.appIcon = appIcon
            self.backingScale = backingScale
            self.style = style
            self.titleColor = titleColor
        }
    }

    /// Renders the transition snapshot for `request` and encodes it as a PNG at
    /// `url`. Returns the descriptor (pixel size + display points) on success.
    @discardableResult
    public static func render(_ request: Request, to url: URL) throws -> AppshotTransitionSnapshot {
        let style = request.style
        let scale = max(request.backingScale, 1)

        let screenshotPixelSize = CGSize(
            width: CGFloat(request.screenshot.width),
            height: CGFloat(request.screenshot.height)
        )
        let layout = style.layout(forScreenshotPixelSize: screenshotPixelSize)
        let canvasSize = layout.canvasSize

        let pixelWidth = Int((canvasSize.width * scale).rounded())
        let pixelHeight = Int((canvasSize.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw AppshotTransitionSnapshotError.cannotCreateContext
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AppshotTransitionSnapshotError.cannotCreateContext
        }

        context.interpolationQuality = .high

        // Flip into a TOP-LEFT origin space scaled so 1 user unit == 1 point.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)

        draw(request: request, layout: layout, context: context)

        guard let image = context.makeImage() else {
            throw AppshotTransitionSnapshotError.encodeFailed
        }
        try encodePNG(image, to: url)

        return AppshotTransitionSnapshot(
            url: url,
            pixelSize: CGSize(width: pixelWidth, height: pixelHeight),
            displayWidth: Double(canvasSize.width),
            displayHeight: Double(canvasSize.height)
        )
    }

    /// Convenience used by the store: loads the screenshot from disk and renders.
    @discardableResult
    public static func render(
        screenshotURL: URL,
        appName: String,
        appIcon: CGImage?,
        backingScale: CGFloat,
        style: AppshotTransitionSnapshotStyle = .default,
        titleColor: CGColor? = nil,
        to url: URL
    ) throws -> AppshotTransitionSnapshot {
        guard let source = CGImageSourceCreateWithURL(screenshotURL as CFURL, nil),
              let screenshot = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AppshotTransitionSnapshotError.unreadableScreenshot
        }

        var request = Request(
            screenshot: screenshot,
            appName: appName,
            appIcon: appIcon,
            backingScale: backingScale,
            style: style
        )
        if let titleColor {
            request.titleColor = titleColor
        }
        return try render(request, to: url)
    }

    // MARK: - Drawing

    private static func draw(
        request: Request,
        layout: AppshotTransitionSnapshotStyle.Layout,
        context: CGContext
    ) {
        let style = request.style
        let cardRect = layout.cardRect
        let cardPath = roundedRectPath(cardRect, radius: style.screenshotCornerRadius)

        // 1. Cast the card's drop shadow by filling an opaque rounded rect. The
        //    screenshot below covers the fill, leaving only the soft shadow.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: style.shadowYOffset),
            blur: style.shadowRadius,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: style.shadowOpacity)
        )
        context.addPath(cardPath)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        // 2. Clip to the rounded card, draw the screenshot, then the bottom fade.
        context.saveGState()
        context.addPath(cardPath)
        context.clip()
        drawImage(request.screenshot, in: cardRect, context: context)
        drawBottomFade(style: style, cardRect: cardRect, context: context)
        context.restoreGState()

        // 3. App icon, overlapping the card's lower edge (no clip).
        if let icon = request.appIcon {
            drawImage(icon, in: layout.iconRect, context: context)
        }

        // 4. Centered, truncated title below the icon.
        let trimmedName = request.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty == false {
            drawTitle(
                trimmedName,
                in: layout.titleBoxRect,
                fontSize: style.titleFontSize,
                color: request.titleColor,
                context: context
            )
        }
    }

    private static func drawBottomFade(
        style: AppshotTransitionSnapshotStyle,
        cardRect: CGRect,
        context: CGContext
    ) {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
            CGColor(srgbRed: 0, green: 0, blue: 0, alpha: style.gradientDimOpacity),
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors,
            locations: [0, 1]
        ) else {
            return
        }

        let startY = cardRect.minY + cardRect.height * style.gradientStartFraction
        let endY = cardRect.minY + cardRect.height * style.gradientEndFraction
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: cardRect.midX, y: startY),
            end: CGPoint(x: cardRect.midX, y: endY),
            options: []
        )
    }

    /// Draws `image` upright into `rect` (top-left coords) inside the globally
    /// flipped (y-down) context by re-flipping locally around the rect.
    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }

    private static func drawTitle(
        _ text: String,
        in box: CGRect,
        fontSize: CGFloat,
        color: CGColor,
        context: CGContext
    ) {
        let font = titleFont(size: fontSize)
        guard let line = makeLine(text, font: font, color: color) else { return }

        // Truncate with an ellipsis to fit the available width.
        let token = makeLine("\u{2026}", font: font, color: color)
        let fitted = CTLineCreateTruncatedLine(line, Double(box.width), .end, token) ?? line

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(fitted, &ascent, &descent, nil))

        let originX = box.minX + max(0, (box.width - lineWidth) / 2)
        let baselineFromTop = (box.height - (ascent + descent)) / 2 + ascent
        let baselineY = box.minY + baselineFromTop

        context.saveGState()
        context.textMatrix = .identity
        // Re-flip locally so CoreText renders upright in the y-down context.
        context.translateBy(x: originX, y: baselineY)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(fitted, context)
        context.restoreGState()
    }

    // MARK: - Helpers

    private static func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, min(rect.width, rect.height) / 2)
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private static func titleFont(size: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let bold = CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold)
        return bold ?? base
    }

    private static func makeLine(_ text: String, font: CTFont, color: CGColor) -> CTLine? {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        guard let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            text as CFString,
            attributes as CFDictionary
        ) else {
            return nil
        }
        return CTLineCreateWithAttributedString(attributed)
    }

    private static func encodePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw AppshotTransitionSnapshotError.encodeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AppshotTransitionSnapshotError.encodeFailed
        }
    }
}
