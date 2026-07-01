import AppKit
import AppshotsCore
import CoreText
import QuartzCore

/// Borderless overlay that plays the capture "flight" using the same layered composition as the
/// persisted `transition-snapshot.png`: a rounded screenshot card, a bottom gradient fade, a centered
/// app icon overlapping the card's lower edge, and a centered app title. The composition is laid out
/// from ``AppshotTransitionSnapshotStyle`` so the live animation matches the rendered PNG, then the
/// whole container flies to the status item and fades out.
///
/// The window spans the screen region between the captured window and the status item so the
/// container layer can scale + translate freely (Core Animation) without clipping.
@MainActor
final class AppshotTransitionOverlayWindow {
    private var window: NSWindow?
    private var containerLayer: CALayer?
    private var iconLayer: CALayer?
    private var titleLayer: CATextLayer?
    private var flashLayer: CALayer?

    private var destinationLocal: CGPoint = .zero
    private var endScale: CGFloat = 1
    private var onComplete: (() -> Void)?

    // Staged timings (seconds). The shutter flashes in then out, the icon + title fade in, the card
    // holds briefly so the shutter reads, then flies into the status item. Because the destination is
    // a tiny menu-bar icon (not a large input box like Codex's), the flight accelerates inward while
    // shrinking and dissolves *during* the final approach — so the card is sucked into the icon rather
    // than landing, resting, then fading (which read as a "stuck" frame on the menu bar).
    private let shutterFadeIn: TimeInterval = 0.05
    private let shutterHold: TimeInterval = 0.05
    private let shutterFadeOut: TimeInterval = 0.24
    private let contentFadeIn: TimeInterval = 0.16
    private let moveHold: TimeInterval = 0.08
    private let flightDuration: TimeInterval = 0.34

    /// Builds and plays the flight. `startFrame` is the captured window's AppKit (bottom-left, screen)
    /// frame, which becomes the card region; the canvas extends below it for the icon + title.
    /// `onComplete` is invoked once when the overlay is torn down (or immediately if it cannot run).
    func present(
        screenshot: NSImage,
        appIcon: NSImage?,
        appName: String,
        startFrame: CGRect,
        destinationPoint: CGPoint,
        style: AppshotTransitionSnapshotStyle = .default,
        onComplete: @escaping () -> Void
    ) {
        self.onComplete = onComplete

        guard startFrame.width > 8,
              startFrame.height > 8,
              startFrame.minX.isFinite,
              startFrame.minY.isFinite,
              startFrame.width.isFinite,
              startFrame.height.isFinite,
              let screenshotCG = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            finish()
            return
        }

        let pixelSize = CGSize(width: screenshotCG.width, height: screenshotCG.height)
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            finish()
            return
        }

        let layout = style.layout(forScreenshotPixelSize: pixelSize)
        guard layout.cardRect.width > 0,
              layout.canvasSize.width > 0,
              layout.canvasSize.height > 0
        else {
            finish()
            return
        }

        // Uniform scale so the layout card (200pt wide at defaults) matches the captured window.
        let scale = startFrame.width / layout.cardRect.width
        guard scale.isFinite, scale > 0 else {
            finish()
            return
        }

        let scaledCanvas = CGSize(
            width: layout.canvasSize.width * scale,
            height: layout.canvasSize.height * scale
        )

        // Place the canvas so its card sub-rect lands exactly over the captured window on screen.
        let canvasLeft = startFrame.minX - style.horizontalPadding * scale
        let canvasTop = startFrame.maxY + style.topPadding * scale
        let compositionScreenRect = CGRect(
            x: canvasLeft,
            y: canvasTop - scaledCanvas.height,
            width: scaledCanvas.width,
            height: scaledCanvas.height
        )

        let region = Self.overlayWindowFrame(composition: compositionScreenRect, destination: destinationPoint)
        let screenScale = (NSScreen.screens.first { $0.frame.intersects(startFrame) } ?? NSScreen.main)?
            .backingScaleFactor ?? style.defaultBackingScale

        let window = NSWindow(
            contentRect: region,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.level = .screenSaver

        let content = NSView(frame: CGRect(origin: .zero, size: region.size))
        content.wantsLayer = true
        content.layer?.masksToBounds = false
        window.contentView = content

        let container = CALayer()
        container.bounds = CGRect(origin: .zero, size: scaledCanvas)
        container.masksToBounds = false

        // Anchor + position the container so the card centre sits over the captured window; the flight
        // then animates that anchor to the status item, shrinking the whole composition with it.
        let cardLocal = Self.containerFrame(layout.cardRect, canvasHeight: scaledCanvas.height, scale: scale)
        let cardCenter = CGPoint(x: cardLocal.midX, y: cardLocal.midY)
        let localOrigin = CGPoint(
            x: compositionScreenRect.minX - region.minX,
            y: compositionScreenRect.minY - region.minY
        )

        let cardCorner = style.screenshotCornerRadius * scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        container.anchorPoint = CGPoint(
            x: cardCenter.x / scaledCanvas.width,
            y: cardCenter.y / scaledCanvas.height
        )
        container.position = CGPoint(x: localOrigin.x + cardCenter.x, y: localOrigin.y + cardCenter.y)
        container.transform = CATransform3DIdentity
        content.layer?.addSublayer(container)

        // Card shadow: an opaque rounded layer behind the screenshot casts the drop shadow; the
        // screenshot (same rounded path) covers the white so only the blurred shadow shows.
        let shadow = CALayer()
        shadow.frame = cardLocal
        shadow.backgroundColor = NSColor.white.cgColor
        shadow.cornerRadius = cardCorner
        shadow.masksToBounds = false
        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowOpacity = Float(style.shadowOpacity)
        shadow.shadowRadius = style.shadowRadius * scale
        shadow.shadowOffset = CGSize(width: 0, height: -style.shadowYOffset * scale)
        shadow.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: cardLocal.size),
            cornerWidth: cardCorner,
            cornerHeight: cardCorner,
            transform: nil
        )
        container.addSublayer(shadow)

        let screenshotLayer = CALayer()
        screenshotLayer.frame = cardLocal
        screenshotLayer.contents = screenshotCG
        screenshotLayer.contentsGravity = .resizeAspectFill
        screenshotLayer.contentsScale = screenScale
        screenshotLayer.cornerRadius = cardCorner
        screenshotLayer.masksToBounds = true
        container.addSublayer(screenshotLayer)

        // Bottom fade: clear from the top down to gradientStartFraction, then clear -> dim to the bottom.
        let gradient = CAGradientLayer()
        gradient.frame = cardLocal
        gradient.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(style.gradientDimOpacity).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        gradient.locations = [
            NSNumber(value: Double(style.gradientStartFraction)),
            NSNumber(value: Double(style.gradientEndFraction)),
        ]
        gradient.cornerRadius = cardCorner
        gradient.masksToBounds = true
        container.addSublayer(gradient)

        // Camera "shutter" flash over the card: pulses in then out at capture (appshotShutterFadeIn/Out).
        let flash = CALayer()
        flash.frame = cardLocal
        flash.backgroundColor = NSColor.white.cgColor
        flash.cornerRadius = cardCorner
        flash.masksToBounds = true
        flash.opacity = 0
        container.addSublayer(flash)
        flashLayer = flash

        if let iconCG = appIcon?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let icon = CALayer()
            icon.frame = Self.containerFrame(layout.iconRect, canvasHeight: scaledCanvas.height, scale: scale)
            icon.contents = iconCG
            icon.contentsGravity = .resizeAspect
            icon.contentsScale = screenScale
            icon.opacity = 0
            container.addSublayer(icon)
            iconLayer = icon
        }

        let title = CATextLayer()
        title.frame = Self.containerFrame(layout.titleBoxRect, canvasHeight: scaledCanvas.height, scale: scale)
        title.string = appName
        let titleFontSize = style.titleFontSize * scale
        let font = NSFont.systemFont(ofSize: titleFontSize, weight: .semibold)
        title.font = CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor, titleFontSize, nil)
        title.fontSize = titleFontSize
        title.alignmentMode = .center
        title.truncationMode = .end
        title.isWrapped = false
        title.foregroundColor = NSColor.labelColor.cgColor
        title.contentsScale = screenScale
        title.opacity = 0
        container.addSublayer(title)
        titleLayer = title

        CATransaction.commit()

        containerLayer = container
        destinationLocal = CGPoint(x: destinationPoint.x - region.minX, y: destinationPoint.y - region.minY)
        endScale = max(28 / startFrame.width, 0.02)

        self.window = window
        window.orderFrontRegardless()

        // The card sits exactly over the live window (same pixels), so it appears seamlessly; only
        // the shutter flash + the new icon/title animate in. The sound fires with the shutter.
        AppshotSoundPlayer.shared.playCapture()
        pulseShutter()
        fadeInContent()

        // Hold briefly so the shutter registers, then fly into the status item.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.moveHold ?? 0.08))
            self?.runFlight()
        }
    }

    /// Camera flash: opacity 0 → peak → 0 (appshotShutterFadeIn / appshotShutterFadeOut).
    private func pulseShutter() {
        guard let flash = flashLayer else { return }
        let total = shutterFadeIn + shutterHold + shutterFadeOut
        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0, 0.7, 0.7, 0]
        pulse.keyTimes = [
            0,
            NSNumber(value: shutterFadeIn / total),
            NSNumber(value: (shutterFadeIn + shutterHold) / total),
            1,
        ]
        pulse.duration = total
        pulse.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeIn),
        ]
        flash.add(pulse, forKey: "shutter")
        flash.opacity = 0
    }

    /// Icon + title ease in (appshotAppIconFadeIn / appshotTitleFadeIn).
    private func fadeInContent() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(contentFadeIn)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        iconLayer?.opacity = 1
        titleLayer?.opacity = 1
        CATransaction.commit()
    }

    /// Flies the whole composition into the status item while shrinking it, dissolving over the final
    /// approach so it is sucked into the icon. Single phase: position + scale accelerate inward
    /// (`easeIn`) and opacity holds full for the first half, then fades out by ~92% of the path — so the
    /// card is already gone before it would "land", leaving no resting frame on the menu bar. Teardown
    /// is driven by the move's completion.
    private func runFlight() {
        guard let container = containerLayer else {
            teardown()
            return
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in self?.teardown() }
        }
        CATransaction.setAnimationDuration(flightDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))

        container.position = destinationLocal
        container.transform = CATransform3DMakeScale(endScale, endScale, 1)

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.5, 0.92]
        fade.duration = flightDuration
        fade.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeIn),
        ]
        fade.isRemovedOnCompletion = false
        fade.fillMode = .forwards
        container.add(fade, forKey: "flightFade")
        container.opacity = 0

        CATransaction.commit()
    }

    private func teardown() {
        window?.orderOut(nil)
        window = nil
        containerLayer = nil
        iconLayer = nil
        titleLayer = nil
        flashLayer = nil
        finish()
    }

    private func finish() {
        let callback = onComplete
        onComplete = nil
        callback?()
    }

    /// Converts a TOP-LEFT layout rect (points) into the container's BOTTOM-LEFT, scaled coordinates.
    private static func containerFrame(_ rect: CGRect, canvasHeight: CGFloat, scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX * scale,
            y: canvasHeight - rect.maxY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// A window frame large enough to hold both the start composition and the destination so the
    /// container layer can fly between them without being clipped.
    private static func overlayWindowFrame(composition: CGRect, destination: CGPoint) -> CGRect {
        let destinationRect = CGRect(x: destination.x - 24, y: destination.y - 24, width: 48, height: 48)
        let screens = NSScreen.screens
        let relevant = screens.filter {
            $0.frame.intersects(composition) || $0.frame.intersects(destinationRect)
        }
        var union = composition.union(destinationRect)
        for screen in (relevant.isEmpty ? screens : relevant) {
            union = union.union(screen.frame)
        }
        return union
    }
}
