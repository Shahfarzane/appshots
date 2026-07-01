import AppKit
import Foundation
import ImageIO

/// Shared, thread-safe downsampled-thumbnail cache used by the popover and the
/// History window so screenshot rows never decode full-resolution PNGs on the
/// main thread.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    func store(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url.path as NSString)
    }

    /// Shared load path used by every screenshot thumbnail view: returns the
    /// cached downsampled image when present, otherwise decodes it off the main
    /// thread, stores it, and returns it. Returns `nil` only when decoding fails.
    func loadThumbnail(for url: URL, maxPixelSize: Int) async -> NSImage? {
        if let cached = image(for: url) {
            return cached
        }

        let loaded = await Task.detached(priority: .utility) {
            ThumbnailCache.makeThumbnail(from: url, maxPixelSize: maxPixelSize)
        }.value

        guard let loaded else { return nil }
        store(loaded, for: url)
        return loaded
    }

    static func makeThumbnail(from url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
