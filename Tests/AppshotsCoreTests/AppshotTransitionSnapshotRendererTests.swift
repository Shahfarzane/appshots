@testable import AppshotsCore
import CoreGraphics
import Foundation
import ImageIO
import Testing

struct AppshotTransitionSnapshotRendererTests {
    @Test func `Renderer writes a decodable transition snapshot PNG`() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("transition-snapshot.png")

        let style = AppshotTransitionSnapshotStyle.default
        let scale: CGFloat = 2
        let request = AppshotTransitionSnapshotRenderer.Request(
            screenshot: solidImage(width: 200, height: 120),
            appName: "Snapshot Demo",
            appIcon: nil,
            backingScale: scale,
            style: style
        )

        let snapshot = try AppshotTransitionSnapshotRenderer.render(request, to: outputURL)

        #expect(snapshot.url == outputURL)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(snapshot.pixelSize.width > 0)
        #expect(snapshot.pixelSize.height > 0)
        #expect(snapshot.displayWidth == Double(style.displayWidth))
        #expect(snapshot.displayWidth == 232)
        #expect(snapshot.displayHeight > 0)
        // A 200x120 screenshot leaves a card plus icon + title rows below it.
        #expect(snapshot.displayHeight > snapshot.displayWidth * 0.5)
        // Pixel size is the point canvas rounded after scaling by the backing scale.
        #expect(snapshot.pixelSize.width == (CGFloat(snapshot.displayWidth) * scale).rounded())
        #expect(snapshot.pixelSize.height == (CGFloat(snapshot.displayHeight) * scale).rounded())

        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == Int(snapshot.pixelSize.width))
        #expect(decoded.height == Int(snapshot.pixelSize.height))
    }

    @Test func `Renderer composes an app icon layer without failing`() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("transition-snapshot.png")

        let request = AppshotTransitionSnapshotRenderer.Request(
            screenshot: solidImage(width: 320, height: 200),
            appName: "App With Icon",
            appIcon: solidImage(width: 64, height: 64),
            backingScale: 2,
            style: .default
        )

        let snapshot = try AppshotTransitionSnapshotRenderer.render(request, to: outputURL)

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(snapshot.displayWidth == 232)
        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == Int(snapshot.pixelSize.width))
        #expect(decoded.height == Int(snapshot.pixelSize.height))
    }

    @Test func `Convenience renderer loads the screenshot from disk`() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screenshotURL = directory.appendingPathComponent("screenshot.png")
        let outputURL = directory.appendingPathComponent("transition-snapshot.png")
        try writePNG(solidImage(width: 200, height: 120), to: screenshotURL)

        let snapshot = try AppshotTransitionSnapshotRenderer.render(
            screenshotURL: screenshotURL,
            appName: "From Disk",
            appIcon: nil,
            backingScale: 2,
            to: outputURL
        )

        #expect(snapshot.url == outputURL)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(snapshot.displayWidth == 232)
        #expect(snapshot.pixelSize.width > 0)
        #expect(snapshot.pixelSize.height > 0)
        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        _ = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test func `Transition layout follows the documented geometry`() {
        let style = AppshotTransitionSnapshotStyle.default
        let layout = style.layout(forScreenshotPixelSize: CGSize(width: 200, height: 120))

        // cardWidth = displayWidth - 2 * horizontalPadding = 200; aspect 0.6 -> cardHeight 120.
        #expect(layout.canvasSize.width == 232)
        #expect(layout.canvasSize.height == 207)
        #expect(layout.cardRect == CGRect(x: 16, y: 16, width: 200, height: 120))
        // Icon is centered horizontally and overlaps the card's lower edge by iconOverlap.
        #expect(layout.iconRect == CGRect(x: 96, y: 122, width: 40, height: 40))
        // Title sits below the icon: titleBoxTop = iconTop + iconSize + titleTopPadding.
        #expect(layout.titleBoxRect.minY == 172)
        #expect(layout.titleBoxRect.height == 23)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("appshots-transition-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func solidImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw TestError.pngWriteFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.pngWriteFailed
        }
    }

    private enum TestError: Error {
        case pngWriteFailed
    }
}
