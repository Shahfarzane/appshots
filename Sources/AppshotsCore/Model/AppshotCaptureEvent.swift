import Foundation

public enum AppshotCaptureStatus: String, Codable, Equatable, Sendable {
    case started
    case metadata
    case axText
    case screenshot
    case completed
    case failed
    case permissionsPending
    case permissionsAbandoned
    case discarded
}

public struct AppshotCaptureEvent: Codable, Equatable, Sendable {
    public var status: AppshotCaptureStatus
    public var requestID: String
    public var createdAt: Date
    public var failureReason: String?
    public var permissionGrantState: String?
    public var record: AppshotRecord?
    public var context: AppshotContext?
    public var surface: AppshotCaptureSurface?
    public var windowID: Int?
    public var windowTitle: String?
    public var windowFrame: CGRect?
    public var screenshotPath: String?
    public var screenshotSize: CGSize?
    public var axNodeCount: Int?
    public var transitionSnapshotPath: String?
    public var transitionSnapshotHeight: Double?
    public var metrics: AppshotCaptureMetrics?

    public init(
        status: AppshotCaptureStatus,
        requestID: String,
        createdAt: Date = Date(),
        failureReason: String? = nil,
        permissionGrantState: String? = nil,
        record: AppshotRecord? = nil,
        context: AppshotContext? = nil,
        surface: AppshotCaptureSurface? = nil,
        windowID: Int? = nil,
        windowTitle: String? = nil,
        windowFrame: CGRect? = nil,
        screenshotPath: String? = nil,
        screenshotSize: CGSize? = nil,
        axNodeCount: Int? = nil,
        transitionSnapshotPath: String? = nil,
        transitionSnapshotHeight: Double? = nil,
        metrics: AppshotCaptureMetrics? = nil
    ) {
        self.status = status
        self.requestID = requestID
        self.createdAt = createdAt
        self.failureReason = failureReason
        self.permissionGrantState = permissionGrantState
        self.record = record
        self.context = context
        self.surface = surface
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.windowFrame = windowFrame
        self.screenshotPath = screenshotPath
        self.screenshotSize = screenshotSize
        self.axNodeCount = axNodeCount
        self.transitionSnapshotPath = transitionSnapshotPath
        self.transitionSnapshotHeight = transitionSnapshotHeight
        self.metrics = metrics
    }
}

public struct AppshotCaptureConfiguration: Codable, Equatable, Sendable {
    public static let `default` = AppshotCaptureConfiguration()

    public var timeoutSeconds: Double

    public init(timeoutSeconds: Double = 120) {
        self.timeoutSeconds = timeoutSeconds
    }
}
