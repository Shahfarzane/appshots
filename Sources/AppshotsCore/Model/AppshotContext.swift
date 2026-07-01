import Foundation

public struct AppshotContext: Codable, Equatable, Sendable {
    public var type: String
    public var appName: String
    public var bundleIdentifier: String
    public var windowTitle: String?
    public var axTree: String
    public var imageName: String?
    public var imagePath: String?
    public var imageDataURL: String?
    public var appIconDataURL: String?
    public var transitionSnapshotDataURL: String?
    public var transitionSnapshotHeight: Double?
    public var transitionSpringResponse: Double?
    public var transitionSpringDampingFraction: Double?
    public var metadata: AppshotRecord

    public init(
        type: String = "appshot",
        appName: String,
        bundleIdentifier: String,
        windowTitle: String?,
        axTree: String,
        imageName: String?,
        imagePath: String?,
        imageDataURL: String?,
        appIconDataURL: String? = nil,
        transitionSnapshotDataURL: String? = nil,
        transitionSnapshotHeight: Double? = nil,
        transitionSpringResponse: Double? = nil,
        transitionSpringDampingFraction: Double? = nil,
        metadata: AppshotRecord
    ) {
        self.type = type
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.axTree = axTree
        self.imageName = imageName
        self.imagePath = imagePath
        self.imageDataURL = imageDataURL
        self.appIconDataURL = appIconDataURL
        self.transitionSnapshotDataURL = transitionSnapshotDataURL
        self.transitionSnapshotHeight = transitionSnapshotHeight
        self.transitionSpringResponse = transitionSpringResponse
        self.transitionSpringDampingFraction = transitionSpringDampingFraction
        self.metadata = metadata
    }
}

public struct AppshotPayload: Codable, Equatable, Sendable {
    public var text: String
    public var imagePath: String?
    public var imageDataURL: String?
    public var context: AppshotContext
    public var metadata: AppshotRecord

    public init(
        text: String,
        imagePath: String?,
        imageDataURL: String?,
        context: AppshotContext,
        metadata: AppshotRecord
    ) {
        self.text = text
        self.imagePath = imagePath
        self.imageDataURL = imageDataURL
        self.context = context
        self.metadata = metadata
    }
}
