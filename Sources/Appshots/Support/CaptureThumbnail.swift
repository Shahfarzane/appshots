import AppKit
import SwiftUI

/// Single screenshot-thumbnail view shared by the popover's recent-shots list
/// and the History window. Parameterized by the screenshot URL, downsampling
/// pixel size, and the frame/corner/border styling each call site needs, so the
/// load + placeholder behavior lives in one place.
struct CaptureThumbnail: View {
    var url: URL?
    var maxPixelSize: Int
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat
    var placeholderFontSize: CGFloat
    var showsBackground: Bool
    var showsBorder: Bool

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: placeholderFontSize))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height)
        .modifier(BackgroundModifier(isEnabled: showsBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .modifier(BorderModifier(isEnabled: showsBorder, cornerRadius: cornerRadius))
        .clipped()
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let loaded = await ThumbnailCache.shared.loadThumbnail(for: url, maxPixelSize: maxPixelSize) {
                image = loaded
            }
        }
    }
}

private struct BackgroundModifier: ViewModifier {
    var isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.background(Color.secondary.opacity(0.08))
        } else {
            content
        }
    }
}

private struct BorderModifier: ViewModifier {
    var isEnabled: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if isEnabled {
            content.overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
        } else {
            content
        }
    }
}
