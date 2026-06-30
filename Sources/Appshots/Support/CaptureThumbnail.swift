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
        .background(showsBackground ? Color.appSurfaceSubtle : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            }
        }
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
