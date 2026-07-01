import CoreGraphics
import Foundation

/// Value descriptor for a rendered transition snapshot PNG. Returned by
/// `AppshotTransitionSnapshotRenderer` and used by the store to populate
/// `AppshotRecord.transitionSnapshotPath` and the context's transition fields.
public struct AppshotTransitionSnapshot: Equatable, Sendable {
    /// On-disk location of the encoded `transition-snapshot.png`.
    public var url: URL
    /// Rendered pixel dimensions (`canvasSize` * backing scale).
    public var pixelSize: CGSize
    /// Canvas width in points (equals `style.displayWidth`).
    public var displayWidth: Double
    /// Canvas height in points.
    public var displayHeight: Double

    public init(url: URL, pixelSize: CGSize, displayWidth: Double, displayHeight: Double) {
        self.url = url
        self.pixelSize = pixelSize
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
    }
}
