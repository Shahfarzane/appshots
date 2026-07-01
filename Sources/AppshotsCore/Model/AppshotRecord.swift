import Foundation

public struct AppshotRecord: Codable, Identifiable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var createdAt: Date
    public var appName: String
    public var bundleID: String
    public var pid: Int32
    public var surface: AppshotCaptureSurface
    public var windowTitle: String
    public var windowID: Int
    public var nodeCount: Int
    public var selectedTextLength: Int
    public var windowFrame: CGRect
    public var screenshotSize: CGSize?
    public var fingerprint: String
    public var directoryPath: String
    public var screenshotPath: String?
    public var pageURL: String?
    public var pageURLPath: String?
    public var axTextPath: String
    public var axJSONPath: String?
    public var appshotTextPath: String
    public var debugTextPath: String?
    public var captureDiagnosticsPath: String?
    public var captureMetricsPath: String?
    public var metadataPath: String
    public var fileBaseName: String
    public var captureNumber: Int
    public var transitionSnapshotPath: String?

    public init(
        schemaVersion: Int = 1,
        id: String,
        createdAt: Date,
        appName: String,
        bundleID: String,
        pid: Int32,
        surface: AppshotCaptureSurface = .window,
        windowTitle: String,
        windowID: Int,
        nodeCount: Int,
        selectedTextLength: Int,
        windowFrame: CGRect,
        screenshotSize: CGSize?,
        fingerprint: String,
        directoryPath: String,
        screenshotPath: String?,
        pageURL: String?,
        pageURLPath: String?,
        axTextPath: String,
        axJSONPath: String?,
        appshotTextPath: String,
        debugTextPath: String? = nil,
        captureDiagnosticsPath: String?,
        captureMetricsPath: String? = nil,
        metadataPath: String,
        fileBaseName: String,
        captureNumber: Int,
        transitionSnapshotPath: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.appName = appName
        self.bundleID = bundleID
        self.pid = pid
        self.surface = surface
        self.windowTitle = windowTitle
        self.windowID = windowID
        self.nodeCount = nodeCount
        self.selectedTextLength = selectedTextLength
        self.windowFrame = windowFrame
        self.screenshotSize = screenshotSize
        self.fingerprint = fingerprint
        self.directoryPath = directoryPath
        self.screenshotPath = screenshotPath
        self.pageURL = pageURL
        self.pageURLPath = pageURLPath
        self.axTextPath = axTextPath
        self.axJSONPath = axJSONPath
        self.appshotTextPath = appshotTextPath
        self.debugTextPath = debugTextPath
        self.captureDiagnosticsPath = captureDiagnosticsPath
        self.captureMetricsPath = captureMetricsPath
        self.metadataPath = metadataPath
        self.fileBaseName = fileBaseName
        self.captureNumber = captureNumber
        self.transitionSnapshotPath = transitionSnapshotPath
    }

    public var directoryURL: URL {
        URL(fileURLWithPath: directoryPath, isDirectory: true)
    }

    public var screenshotURL: URL? {
        screenshotPath.map(URL.init(fileURLWithPath:))
    }

    public var axTextURL: URL {
        URL(fileURLWithPath: axTextPath)
    }

    public var axJSONURL: URL? {
        axJSONPath.map(URL.init(fileURLWithPath:))
    }

    public var appshotTextURL: URL {
        URL(fileURLWithPath: appshotTextPath)
    }

    public var debugTextURL: URL? {
        debugTextPath.map(URL.init(fileURLWithPath:))
    }

    public var captureMetricsURL: URL? {
        captureMetricsPath.map(URL.init(fileURLWithPath:))
    }

    public var metadataURL: URL {
        URL(fileURLWithPath: metadataPath)
    }

    public var transitionSnapshotURL: URL? {
        transitionSnapshotPath.map(URL.init(fileURLWithPath:))
    }

    public var referenceText: String {
        """
        # Appshot

        A macOS appshot was captured for \(appName).

        Read the Codex-style appshot prompt:
        \(appshotTextPath)

        Files:
        - screenshot: \(screenshotPath ?? "not captured")
        - page URL: \(pageURL ?? "not captured")
        - accessibility tree: \(axTextPath)
        - accessibility tree JSON: \(axJSONPath ?? "not captured")
        - debug prompt: \(debugTextPath ?? "not captured")
        - capture diagnostics: \(captureDiagnosticsPath ?? "not captured")
        - capture metrics: \(captureMetricsPath ?? "not captured")
        - metadata: \(metadataPath)
        - capture directory: \(directoryPath)

        Fast path:
        cat ~/.appshots/latest.md
        cat ~/.appshots/latest.txt
        """
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case createdAt
        case appName
        case bundleID
        case pid
        case surface
        case windowTitle
        case windowID
        case nodeCount
        case selectedTextLength
        case windowFrame
        case screenshotSize
        case fingerprint
        case directoryPath
        case screenshotPath
        case pageURL
        case pageURLPath
        case axTextPath
        case axJSONPath
        case appshotTextPath
        case debugTextPath
        case captureDiagnosticsPath
        case captureMetricsPath
        case metadataPath
        case fileBaseName
        case captureNumber
        case transitionSnapshotPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        appName = try container.decode(String.self, forKey: .appName)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        pid = try container.decode(Int32.self, forKey: .pid)
        surface = try container.decodeIfPresent(AppshotCaptureSurface.self, forKey: .surface) ?? .window
        windowTitle = try container.decode(String.self, forKey: .windowTitle)
        windowID = try container.decode(Int.self, forKey: .windowID)
        nodeCount = try container.decode(Int.self, forKey: .nodeCount)
        selectedTextLength = try container.decode(Int.self, forKey: .selectedTextLength)
        windowFrame = try container.decode(CGRect.self, forKey: .windowFrame)
        screenshotSize = try container.decodeIfPresent(CGSize.self, forKey: .screenshotSize)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        directoryPath = try container.decode(String.self, forKey: .directoryPath)
        screenshotPath = try container.decodeIfPresent(String.self, forKey: .screenshotPath)
        pageURL = try container.decodeIfPresent(String.self, forKey: .pageURL)
        pageURLPath = try container.decodeIfPresent(String.self, forKey: .pageURLPath)
        axTextPath = try container.decode(String.self, forKey: .axTextPath)
        axJSONPath = try container.decodeIfPresent(String.self, forKey: .axJSONPath)
        appshotTextPath = try container.decode(String.self, forKey: .appshotTextPath)
        debugTextPath = try container.decodeIfPresent(String.self, forKey: .debugTextPath)
        captureDiagnosticsPath = try container.decodeIfPresent(String.self, forKey: .captureDiagnosticsPath)
        captureMetricsPath = try container.decodeIfPresent(String.self, forKey: .captureMetricsPath)
        metadataPath = try container.decode(String.self, forKey: .metadataPath)
        fileBaseName = try container.decode(String.self, forKey: .fileBaseName)
        captureNumber = try container.decode(Int.self, forKey: .captureNumber)
        transitionSnapshotPath = try container.decodeIfPresent(String.self, forKey: .transitionSnapshotPath)
    }
}

public enum AppshotStoreError: LocalizedError {
    case missingSnapshotMetadata
    case unreadableScreenshot(String)
    case imageTooLarge(path: String, bytes: Int, limit: Int)
    case missingCaptureMetrics(String)

    public var errorDescription: String? {
        switch self {
        case .missingSnapshotMetadata:
            return "App state output did not include snapshot metadata."
        case .unreadableScreenshot(let path):
            return "Could not read screenshot at \(path)."
        case .imageTooLarge(let path, let bytes, let limit):
            return "Screenshot at \(path) is too large to inline (\(bytes) bytes, limit \(limit) bytes)."
        case .missingCaptureMetrics(let id):
            return "Capture has no metrics: \(id)."
        }
    }
}
