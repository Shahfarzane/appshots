import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

public struct ScreenshotCompression: Codable, Equatable, Sendable {
    public static let foregroundDefault = ScreenshotCompression()
    public static let appshotStored = ScreenshotCompression(
        maxLongEdgePixels: 8192,
        maxPixelArea: 67_108_864,
        jpegQuality: 0.92
    )

    public var maxLongEdgePixels: Int
    public var maxPixelArea: Int
    public var jpegQuality: Double

    public init(
        maxLongEdgePixels: Int = 1568,
        maxPixelArea: Int = 629_145,
        jpegQuality: Double = 0.82
    ) {
        self.maxLongEdgePixels = maxLongEdgePixels
        self.maxPixelArea = maxPixelArea
        self.jpegQuality = jpegQuality
    }

    public func scaledPixelSize(width srcW: Int, height srcH: Int) -> CGSize {
        let longEdge = max(srcW, srcH)
        let area = srcW * srcH

        let maxLongEdge = max(1, self.maxLongEdgePixels)
        let maxPixelArea = max(1, self.maxPixelArea)
        let longEdgeScale = CGFloat(maxLongEdge) / CGFloat(max(longEdge, 1))
        let areaScale = sqrt(CGFloat(maxPixelArea) / CGFloat(max(area, 1)))
        let scale = min(1.0, min(longEdgeScale, areaScale))

        return CGSize(
            width: max(1, Int((CGFloat(srcW) * scale).rounded())),
            height: max(1, Int((CGFloat(srcH) * scale).rounded()))
        )
    }
}

public struct AppshotCaptureDiagnostics: Codable, Equatable, Sendable {
    public var backend: String
    public var windowID: Int
    public var rawPixelSize: CGSizeCodable
    public var storedPixelSize: CGSizeCodable
    public var scaleFactor: Double
    public var compression: ScreenshotCompression
    public var screenCaptureKitFailureReason: String?
    public var captureDurationMs: Double
    public var rawBytes: Int?
    public var storedBytes: Int?
    public var downscaleReason: String?

    public init(
        backend: String,
        windowID: Int,
        rawPixelSize: CGSizeCodable,
        storedPixelSize: CGSizeCodable,
        scaleFactor: Double,
        compression: ScreenshotCompression,
        screenCaptureKitFailureReason: String?,
        captureDurationMs: Double,
        rawBytes: Int? = nil,
        storedBytes: Int? = nil,
        downscaleReason: String? = nil
    ) {
        self.backend = backend
        self.windowID = windowID
        self.rawPixelSize = rawPixelSize
        self.storedPixelSize = storedPixelSize
        self.scaleFactor = scaleFactor
        self.compression = compression
        self.screenCaptureKitFailureReason = screenCaptureKitFailureReason
        self.captureDurationMs = captureDurationMs
        self.rawBytes = rawBytes
        self.storedBytes = storedBytes
        self.downscaleReason = downscaleReason
    }
}

enum BackgroundWindowCapture {
    static let diagnosticsSidecarExtension = "diagnostics.json"

    static func prewarm() {
        ScreenCaptureKitWindowCapture.prewarm()
    }

    static func captureWindowScreenshot(
        windowID: Int,
        compression: ScreenshotCompression = .foregroundDefault
    ) -> (url: URL, size: CGSize)? {
        let startedAt = Date()
        guard let capture = captureWindowImage(windowID: windowID) else {
            return nil
        }

        let scaled = scaleToLimits(capture.image, compression: compression)
        let rawSize = CGSize(width: capture.image.width, height: capture.image.height)
        let storedSize = CGSize(width: scaled.width, height: scaled.height)
        let diagnostics = AppshotCaptureDiagnostics(
            backend: capture.backend,
            windowID: windowID,
            rawPixelSize: CGSizeCodable(rawSize),
            storedPixelSize: CGSizeCodable(storedSize),
            scaleFactor: scaleFactor(from: rawSize, to: storedSize),
            compression: compression,
            screenCaptureKitFailureReason: capture.screenCaptureKitFailureReason,
            captureDurationMs: Date().timeIntervalSince(startedAt) * 1000,
            rawBytes: capture.image.bytesPerRow * capture.image.height,
            downscaleReason: downscaleReason(rawSize: rawSize, storedSize: storedSize, compression: compression)
        )

        return writePNG(
            scaled,
            prefix: "appshots-capture-engine-capture",
            diagnostics: diagnostics
        ).map {
            (url: $0, size: CGSize(width: scaled.width, height: scaled.height))
        }
    }

    static func diagnosticsURL(for screenshotURL: URL) -> URL {
        screenshotURL.appendingPathExtension(diagnosticsSidecarExtension)
    }

    static func scaledPixelSize(
        width srcW: Int,
        height srcH: Int,
        compression: ScreenshotCompression
    ) -> CGSize {
        compression.scaledPixelSize(width: srcW, height: srcH)
    }

    private struct BackendCapture {
        var image: CGImage
        var backend: String
        var screenCaptureKitFailureReason: String?
    }

    private static func captureWindowImage(windowID: Int) -> BackendCapture? {
        let screenCaptureKitCapture = ScreenCaptureKitWindowCapture.captureWindowImage(windowID: windowID)
        if let image = screenCaptureKitCapture.image {
            return BackendCapture(
                image: image,
                backend: "ScreenCaptureKit.SCScreenshotManager",
                screenCaptureKitFailureReason: nil
            )
        }

        if let image = LegacyCGWindowCapture.captureWindowImage(windowID: windowID) {
            return BackendCapture(
                image: image,
                backend: "CoreGraphics.CGWindowListCreateImage",
                screenCaptureKitFailureReason: screenCaptureKitCapture.failureReason
            )
        }

        return nil
    }

    private static func scaleToLimits(
        _ image: CGImage,
        compression: ScreenshotCompression
    ) -> CGImage {
        let srcW = image.width
        let srcH = image.height
        let scaledSize = scaledPixelSize(width: srcW, height: srcH, compression: compression)
        let dstW = Int(scaledSize.width)
        let dstH = Int(scaledSize.height)
        guard dstW != srcW || dstH != srcH else {
            // No downscaling needed — keep the raw capture (with its natural
            // transparent window corners) untouched.
            return image
        }

        return redraw(image, width: dstW, height: dstH) ?? image
    }

    /// Redraws into an alpha-preserving context so the window's transparent
    /// rounded corners stay transparent (no white flattening / framing).
    private static func redraw(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = makeAlphaRGBContext(width: width, height: height) else {
            return nil
        }
        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func makeAlphaRGBContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }

    private static func scaleFactor(from rawSize: CGSize, to storedSize: CGSize) -> Double {
        guard rawSize.width > 0, rawSize.height > 0 else {
            return 1
        }
        let widthScale = storedSize.width / rawSize.width
        let heightScale = storedSize.height / rawSize.height
        return (widthScale + heightScale) / 2
    }

    private static func writePNG(
        _ image: CGImage,
        prefix: String,
        diagnostics: AppshotCaptureDiagnostics
    ) -> URL? {
        do {
            var diagnostics = diagnostics
            try SnapshotCacheStore.ensureRootDirectory()
            let url = SnapshotCacheStore.rootURL.appendingPathComponent(
                "\(prefix)-\(UUID().uuidString.lowercased()).png"
            )
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                return nil
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                return nil
            }
            let storedBytes = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
            diagnostics.storedBytes = storedBytes
            try writeDiagnostics(diagnostics, for: url)
            AppshotCaptureMetricsContext.setScreenshot(
                backend: diagnostics.backend,
                rawBytes: diagnostics.rawBytes,
                storedBytes: storedBytes
            )
            return url
        } catch {
            return nil
        }
    }

    private static func writeDiagnostics(
        _ diagnostics: AppshotCaptureDiagnostics,
        for screenshotURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(diagnostics)
        try data.write(to: diagnosticsURL(for: screenshotURL), options: .atomic)
    }

    private static func downscaleReason(
        rawSize: CGSize,
        storedSize: CGSize,
        compression: ScreenshotCompression
    ) -> String? {
        guard storedSize.width < rawSize.width || storedSize.height < rawSize.height else {
            return nil
        }
        let rawLongEdge = Int(max(rawSize.width, rawSize.height))
        let rawArea = Int(rawSize.width * rawSize.height)
        if rawLongEdge > compression.maxLongEdgePixels, rawArea > compression.maxPixelArea {
            return "long_edge_and_pixel_area_limits"
        }
        if rawLongEdge > compression.maxLongEdgePixels {
            return "long_edge_limit"
        }
        if rawArea > compression.maxPixelArea {
            return "pixel_area_limit"
        }
        return "scaled"
    }
}

private enum ScreenCaptureKitWindowCapture {
    private final class CaptureBox: @unchecked Sendable {
        var image: CGImage?
        var failureReason: String?
    }

    private actor PrewarmState {
        var didRun = false
        var isRunning = false

        func begin() -> Bool {
            guard didRun == false, isRunning == false else {
                return false
            }
            isRunning = true
            return true
        }

        func finish() {
            didRun = true
            isRunning = false
        }
    }

    private static let prewarmState = PrewarmState()
    private static let shareableContentCache = ShareableContentCache(ttlSeconds: 1.0)

    static func prewarm() {
        Task.detached(priority: .utility) {
            guard await prewarmState.begin() else { return }
            let started = DispatchTime.now()
            _ = try? await shareableContentCache.content()
            let elapsedMs = (DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
            await prewarmState.finish()
            AppLog.capture.debug("screen capture kit prewarm finished ms=\(elapsedMs, privacy: .public)")
        }
    }

    static func captureWindowImage(windowID: Int) -> (image: CGImage?, failureReason: String?) {
        let box = CaptureBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached(priority: .userInitiated) {
            do {
                let contentStart = DispatchTime.now().uptimeNanoseconds
                let cachedContent = try await shareableContentCache.content()
                AppshotCaptureMetricsContext.recordPhase(
                    "SCK shareable content fetch",
                    started: contentStart,
                    ended: DispatchTime.now().uptimeNanoseconds,
                    detail: cachedContent.cacheHit ? "cache_hit" : "cache_miss"
                )
                let matchStart = DispatchTime.now().uptimeNanoseconds
                guard let window = cachedContent.content.windows.first(where: { Int($0.windowID) == windowID }) else {
                    AppshotCaptureMetricsContext.recordPhase(
                        "SCK window match",
                        started: matchStart,
                        ended: DispatchTime.now().uptimeNanoseconds,
                        detail: "miss:\(windowID)"
                    )
                    box.failureReason = "window_not_found_in_shareable_content"
                    semaphore.signal()
                    return
                }
                AppshotCaptureMetricsContext.recordPhase(
                    "SCK window match",
                    started: matchStart,
                    ended: DispatchTime.now().uptimeNanoseconds,
                    detail: "hit:\(windowID)"
                )

                let configuration = SCStreamConfiguration()
                let scale = backingScaleFactor(for: window.frame)
                configuration.width = max(1, Int((window.frame.width * scale).rounded()))
                configuration.height = max(1, Int((window.frame.height * scale).rounded()))
                configuration.showsCursor = false

                let filter = SCContentFilter(desktopIndependentWindow: window)
                box.image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            } catch {
                box.failureReason = error.localizedDescription
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            return (nil, "screen_capture_kit_timeout")
        }

        return (box.image, box.failureReason)
    }

    private static func backingScaleFactor(for frame: CGRect) -> CGFloat {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)

        // `SCWindow.frame` is in Core Graphics global display coordinates
        // (top-left origin), which matches `CGGetDisplaysWithPoint`. Resolving
        // the display there (rather than against `NSScreen.frame`, which uses
        // AppKit's bottom-left origin) avoids picking the wrong screen — and
        // thus the wrong scale factor — on vertically arranged multi-monitor
        // setups. The matching `NSScreen` then provides the backing scale.
        var displayID = CGDirectDisplayID(0)
        var matchCount: UInt32 = 0
        if CGGetDisplaysWithPoint(midpoint, 1, &displayID, &matchCount) == .success,
           matchCount > 0,
           let screen = NSScreen.screens.first(where: { screen in
               (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
           }) {
            return screen.backingScaleFactor
        }

        return NSScreen.main?.backingScaleFactor ?? 2
    }
}

private final class ShareableContentCache: @unchecked Sendable {
    private let ttlSeconds: TimeInterval
    private let lock = NSLock()
    private var cachedContent: SCShareableContent?
    private var cachedAt: Date?

    init(ttlSeconds: TimeInterval) {
        self.ttlSeconds = ttlSeconds
    }

    func content() async throws -> (content: SCShareableContent, cacheHit: Bool) {
        let now = Date()
        if let cached = lock.withLock({ () -> SCShareableContent? in
            guard let cachedContent,
                  let cachedAt,
                  now.timeIntervalSince(cachedAt) <= ttlSeconds
            else {
                return nil
            }
            return cachedContent
        }) {
            return (cached, true)
        }

        let fresh = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        lock.withLock {
            cachedContent = fresh
            cachedAt = Date()
        }
        return (fresh, false)
    }
}

private enum LegacyCGWindowCapture {
    // Keep the legacy synchronous window capture backend behind dynamic lookup so
    // builds do not directly reference the deprecated macOS 14 declaration.
    private typealias CreateImageFn = @convention(c) (
        CGRect,
        UInt32,
        CGWindowID,
        UInt32
    ) -> Unmanaged<CGImage>?

    private static let createImage: CreateImageFn? = {
        _ = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY
        )
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CreateImageFn.self)
    }()

    static func captureWindowImage(windowID: Int) -> CGImage? {
        let imageOptions: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]
        return createImage?(
            .null,
            CGWindowListOption.optionIncludingWindow.rawValue,
            CGWindowID(windowID),
            imageOptions.rawValue
        )?.takeRetainedValue()
    }
}
