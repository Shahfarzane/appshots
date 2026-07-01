import Foundation

struct SnapshotCacheFile: Codable {
    var metadata: CaptureMetadata
}

enum SnapshotCacheStore {
    static var rootURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "appshots-capture-engine",
            isDirectory: true
        )
    }

    static func ensureRootDirectory() throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    static func metadataURL(for snapshotID: String) -> URL {
        rootURL.appendingPathComponent("\(snapshotID).json")
    }

    static func screenshotURL(for snapshotID: String, pathExtension: String = "png") -> URL {
        let ext = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "png"
            : pathExtension
        return rootURL.appendingPathComponent("\(snapshotID).\(ext)")
    }

    static func save(snapshot: RuntimeAppSnapshot) throws -> CaptureMetadata {
        try ensureRootDirectory()

        let snapshotID = UUID().uuidString.lowercased()
        let screenshotPath: String?
        let screenshotSize: CGSizeCodable?

        if let sourceScreenshotURL = snapshot.screenshotURL {
            let targetURL = screenshotURL(
                for: snapshotID,
                pathExtension: sourceScreenshotURL.pathExtension
            )
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: sourceScreenshotURL, to: targetURL)
            try copyDiagnosticsSidecar(from: sourceScreenshotURL, to: targetURL)
            screenshotPath = targetURL.path
            screenshotSize = snapshot.screenshotSize.map(CGSizeCodable.init)
        } else {
            screenshotPath = nil
            screenshotSize = nil
        }

        let metadata = CaptureMetadata(
            id: snapshotID,
            createdAt: Date(),
            appName: snapshot.app.localizedName ?? snapshot.app.bundleIdentifier ?? "Unknown",
            bundleID: snapshot.app.bundleIdentifier ?? "",
            pid: snapshot.app.processIdentifier,
            windowTitle: snapshot.windowTitle,
            windowID: snapshot.windowID,
            windowFrame: CGRectCodable(snapshot.windowFrame),
            screenshotPath: screenshotPath,
            screenshotSize: screenshotSize,
            fingerprint: snapshot.fingerprint,
            nodeSignatures: nodeSignatures(for: snapshot.nodes)
        )

        let data = try JSONEncoder.snapshotCache.encode(SnapshotCacheFile(metadata: metadata))
        try data.write(to: metadataURL(for: snapshotID), options: .atomic)
        return metadata
    }

    private static func copyDiagnosticsSidecar(from sourceURL: URL, to targetURL: URL) throws {
        let sourceDiagnosticsURL = BackgroundWindowCapture.diagnosticsURL(for: sourceURL)
        guard FileManager.default.fileExists(atPath: sourceDiagnosticsURL.path) else {
            return
        }

        let targetDiagnosticsURL = BackgroundWindowCapture.diagnosticsURL(for: targetURL)
        if FileManager.default.fileExists(atPath: targetDiagnosticsURL.path) {
            try FileManager.default.removeItem(at: targetDiagnosticsURL)
        }
        try FileManager.default.copyItem(at: sourceDiagnosticsURL, to: targetDiagnosticsURL)
    }
}

extension JSONEncoder {
    static var snapshotCache: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
