import AppKit
import AppshotsCore
import UniformTypeIdentifiers

@MainActor
final class AppshotCaptureAnimator {
    private var activeOverlays: [AppshotTransitionOverlayWindow] = []

    func animate(record: AppshotRecord, image: NSImage?, destinationPoint: CGPoint?) {
        guard let image = image ?? record.screenshotURL.flatMap({ NSImage(contentsOf: $0) })
        else {
            return
        }

        let startFrame = startFrame(for: record, image: image)
        present(
            image: image,
            appName: record.appName,
            bundleID: record.bundleID,
            startFrame: startFrame,
            destinationPoint: destinationPoint
        )
    }

    func animate(
        windowFrame: CGRect,
        image: NSImage,
        appName: String,
        bundleID: String,
        destinationPoint: CGPoint?
    ) {
        let startFrame = appKitFrame(fromAXFrame: windowFrame) ?? fallbackStartFrame(for: image)
        present(
            image: image,
            appName: appName,
            bundleID: bundleID,
            startFrame: startFrame,
            destinationPoint: destinationPoint
        )
    }

    private func present(
        image: NSImage,
        appName: String,
        bundleID: String,
        startFrame: CGRect,
        destinationPoint: CGPoint?
    ) {
        guard startFrame.width > 8, startFrame.height > 8 else {
            return
        }

        let destination = destinationPoint ?? fallbackDestinationPoint(from: startFrame)
        let icon = appIcon(forBundleID: bundleID)

        let overlay = AppshotTransitionOverlayWindow()
        activeOverlays.append(overlay)
        overlay.present(
            screenshot: image,
            appIcon: icon,
            appName: appName,
            startFrame: startFrame,
            destinationPoint: destination,
            style: .default
        ) { [weak self, weak overlay] in
            guard let self, let overlay else { return }
            self.activeOverlays.removeAll { $0 === overlay }
        }
    }

    private func appIcon(forBundleID bundleID: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        if bundleID.isEmpty == false,
           let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            return workspace.icon(forFile: url.path)
        }

        return workspace.icon(for: .application)
    }

    private func startFrame(for record: AppshotRecord, image: NSImage) -> CGRect {
        if let frame = appKitFrame(fromAXFrame: record.windowFrame),
           frame.isUsableForAppshotAnimation {
            return frame
        }

        return fallbackStartFrame(for: image)
    }

    private func fallbackStartFrame(for image: NSImage) -> CGRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let imageSize = image.size
        let maxWidth = screenFrame.width * 0.72
        let maxHeight = screenFrame.height * 0.72
        let scale = min(maxWidth / max(imageSize.width, 1), maxHeight / max(imageSize.height, 1), 1)
        let size = CGSize(width: max(imageSize.width * scale, 240), height: max(imageSize.height * scale, 160))
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func fallbackDestinationPoint(from startFrame: CGRect) -> CGPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(startFrame) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        return CGPoint(
            x: frame.maxX - frame.width * 0.30,
            y: frame.maxY - frame.height * 0.30
        )
    }

    private func appKitFrame(fromAXFrame axFrame: CGRect) -> CGRect? {
        guard axFrame.isUsableForAppshotAnimation else {
            return nil
        }

        guard let space = displaySpace(containingAXPoint: CGPoint(x: axFrame.midX, y: axFrame.midY)) else {
            return axFrame
        }

        let x = space.appKitFrame.minX + (axFrame.minX - space.axFrame.minX)
        let y = space.appKitFrame.maxY - (axFrame.maxY - space.axFrame.minY)
        return CGRect(x: x, y: y, width: axFrame.width, height: axFrame.height)
    }

    private func displaySpace(containingAXPoint point: CGPoint) -> DisplaySpace? {
        let spaces = NSScreen.screens.compactMap(DisplaySpace.init(screen:))
        return spaces.first { $0.axFrame.contains(point) }
            ?? spaces.min {
                $0.axFrame.distanceSquared(to: point) < $1.axFrame.distanceSquared(to: point)
            }
    }
}

private struct DisplaySpace {
    let appKitFrame: CGRect
    let axFrame: CGRect

    init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return nil
        }

        appKitFrame = screen.frame
        axFrame = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }
}

private extension CGRect {
    var isUsableForAppshotAnimation: Bool {
        minX.isFinite &&
            minY.isFinite &&
            width.isFinite &&
            height.isFinite &&
            width > 8 &&
            height > 8
    }

    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx: CGFloat = if point.x < minX {
            minX - point.x
        } else if point.x > maxX {
            point.x - maxX
        } else {
            0
        }

        let dy: CGFloat = if point.y < minY {
            minY - point.y
        } else if point.y > maxY {
            point.y - maxY
        } else {
            0
        }

        return (dx * dx) + (dy * dy)
    }
}
