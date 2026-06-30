import Foundation
import ImageIO

public struct AppshotStore: Sendable {
    public static let transitionSnapshotDisplayWidth: Double = 232
    public static let transitionSpringResponse: Double = 0.35
    public static let transitionSpringDampingFraction: Double = 0.73

    private let customRootURL: URL?
    var fileManager: FileManager { .default }

    public init(rootURL: URL? = nil) {
        customRootURL = rootURL
    }

    public var rootURL: URL {
        customRootURL ??
            fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".appshots", isDirectory: true)
    }

    public var snapshotsURL: URL {
        rootURL.appendingPathComponent("snapshots", isDirectory: true)
    }

    public var latestTextURL: URL {
        rootURL.appendingPathComponent("latest.txt")
    }

    public var latestPromptURL: URL {
        rootURL.appendingPathComponent("latest.md")
    }

    public var latestMetadataURL: URL {
        rootURL.appendingPathComponent("latest.json")
    }

    public var indexURL: URL {
        rootURL.appendingPathComponent("index.json")
    }

    public func ensureRootDirectory() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
    }

    public func removeCapture(_ record: AppshotRecord) throws {
        let directoryURL = record.directoryURL
        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }
    }

    public func recentCaptures(limit: Int) -> [AppshotRecord] {
        Array(loadIndex().prefix(limit))
    }

    public func allCaptures() -> [AppshotRecord] {
        loadIndex()
    }

    public func latestCapture() -> AppshotRecord? {
        loadIndex().first
    }

    public func modelPrompt(for record: AppshotRecord) throws -> String {
        let appStateText = try appStateText(for: record)
        return modelFacingAppshotText(record: record, appStateText: appStateText)
    }

    public func payload(for record: AppshotRecord, includeImageData: Bool = true) throws -> AppshotPayload {
        let context = try appshotContext(for: record, includeImageData: includeImageData)

        return AppshotPayload(
            text: try modelPrompt(for: record),
            imagePath: context.imagePath,
            imageDataURL: context.imageDataURL,
            context: context,
            metadata: record
        )
    }

    public func appshotContext(
        for record: AppshotRecord,
        includeImageData: Bool = true,
        includeAppIconData: Bool = true
    ) throws -> AppshotContext {
        try appshotContext(
            for: record,
            appStateText: try appStateText(for: record),
            includeImageData: includeImageData,
            includeAppIconData: includeAppIconData
        )
    }

    /// Builds the context from an already-rendered app-state string, skipping the disk
    /// read-back + JSON decode + re-render that `appStateText(for:)` performs. The capture
    /// save path holds the freshly rendered text and should use this to stay off that round-trip.
    func appshotContext(
        for record: AppshotRecord,
        appStateText: String,
        includeImageData: Bool = true,
        includeAppIconData: Bool = true
    ) throws -> AppshotContext {
        let imageDataURL: String?
        if includeImageData, let screenshotURL = record.screenshotURL {
            imageDataURL = try pngDataURL(from: screenshotURL)
        } else {
            imageDataURL = nil
        }

        return AppshotContext(
            appName: record.appName,
            bundleIdentifier: record.bundleID,
            windowTitle: record.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : record.windowTitle,
            axTree: trimAppStateForAppshot(appStateText),
            imageName: record.screenshotURL?.lastPathComponent,
            imagePath: record.screenshotPath,
            imageDataURL: imageDataURL,
            appIconDataURL: includeAppIconData ? appIconDataURL(for: record) : nil,
            transitionSnapshotDataURL: includeImageData ? (transitionSnapshotDataURL(for: record) ?? imageDataURL) : nil,
            transitionSnapshotHeight: transitionSnapshotHeight(for: record),
            transitionSpringResponse: Self.transitionSpringResponse,
            transitionSpringDampingFraction: Self.transitionSpringDampingFraction,
            metadata: record
        )
    }

    public func captureMetrics(for record: AppshotRecord) throws -> AppshotCaptureMetrics {
        guard let metricsURL = record.captureMetricsURL,
              fileManager.fileExists(atPath: metricsURL.path)
        else {
            throw AppshotStoreError.missingCaptureMetrics(record.id)
        }

        let data = try Data(contentsOf: metricsURL)
        return try jsonDecoder().decode(AppshotCaptureMetrics.self, from: data)
    }

    public func appendMetricPhase(
        for record: AppshotRecord,
        name: String,
        durationMs: Double = 0,
        detail: String? = nil
    ) throws {
        guard let metricsURL = record.captureMetricsURL,
              fileManager.fileExists(atPath: metricsURL.path)
        else {
            return
        }

        var metrics = try captureMetrics(for: record)
        let offset = max(0, Date().timeIntervalSince(metrics.startedAt) * 1000 - durationMs)
        metrics.phases.append(CapturePhaseMetric(
            name: name,
            startedAtOffsetMs: offset,
            durationMs: durationMs,
            detail: detail
        ))
        let data = try jsonEncoder().encode(metrics)
        try data.write(to: metricsURL, options: .atomic)
    }

    public func completedEvent(
        for record: AppshotRecord,
        requestID: String? = nil,
        includeImageData: Bool = false,
        includeContext: Bool = false
    ) throws -> AppshotCaptureEvent {
        AppshotCaptureEvent(
            status: .completed,
            requestID: requestID ?? record.id,
            createdAt: record.createdAt,
            record: record,
            context: includeContext ? try appshotContext(
                for: record,
                includeImageData: includeImageData,
                includeAppIconData: false
            ) : nil
        )
    }

    public func searchCaptures(query: String, limit: Int = 20) -> [AppshotRecord] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedQuery.isEmpty == false else {
            return Array(loadIndex().prefix(limit))
        }

        return Array(loadIndex().filter { record in
            searchableText(for: record).lowercased().contains(normalizedQuery)
        }.prefix(limit))
    }

    public func deleteCapture(id: String) throws -> Bool {
        var records = loadIndex()
        guard let record = records.first(where: { $0.id == id }) else {
            return false
        }

        try removeCapture(record)
        records.removeAll { $0.id == id }
        let data = try jsonEncoder().encode(records)
        try data.write(to: indexURL, options: .atomic)

        if let latest = records.first,
           let appshotText = try? String(contentsOf: latest.appshotTextURL, encoding: .utf8) {
            try writeLatestPointers(record: latest, appshotText: appshotText)
        } else {
            try removeLatestPointers()
        }

        AppLog.store.notice("deleted appshot id=\(id, privacy: .public)")
        return true
    }

    public func deleteCaptures(ids: [String]) throws -> Int {
        var deleted = 0
        for id in ids where try deleteCapture(id: id) {
            deleted += 1
        }
        return deleted
    }

    public func clearAll() throws {
        for record in loadIndex() {
            try removeCapture(record)
        }

        if fileManager.fileExists(atPath: indexURL.path) {
            try fileManager.removeItem(at: indexURL)
        }

        if fileManager.fileExists(atPath: snapshotsURL.path) {
            let contents = try fileManager.contentsOfDirectory(
                at: snapshotsURL,
                includingPropertiesForKeys: nil
            )
            for url in contents {
                try fileManager.removeItem(at: url)
            }
        }

        try removeLatestPointers()
        AppLog.store.notice("cleared all appshots")
    }

    public func save(
        target: FrontmostAppTarget,
        output: CaptureOutput,
        structuredState: CapturedAppState? = nil,
        metricsRecorder: AppshotCaptureMetricsRecorder? = nil
    ) throws -> AppshotRecord {
        guard let metadata = output.metadata else {
            AppLog.store.error("save aborted: missing snapshot metadata for app=\(target.name, privacy: .public)")
            throw AppshotStoreError.missingSnapshotMetadata
        }

        try ensureRootDirectory()

        let appName = metadata.appName.isEmpty ? target.name : metadata.appName
        let bundleID = metadata.bundleID.isEmpty ? target.bundleID : metadata.bundleID
        let fileBaseName = sanitizedFileBaseName(appName: appName, bundleID: bundleID)
        let captureNumber = nextCaptureNumber()
        let captureID = captureID(fileBaseName: fileBaseName, captureNumber: captureNumber, date: metadata.createdAt)
        let dayURL = snapshotsURL.appendingPathComponent(dayFolderName(for: metadata.createdAt), isDirectory: true)
        let captureURL = dayURL.appendingPathComponent(captureID, isDirectory: true)
        try fileManager.createDirectory(at: captureURL, withIntermediateDirectories: true)

        let screenshotURL = captureURL.appendingPathComponent("screenshot.png")
        let pageURLFileURL = captureURL.appendingPathComponent("page_url.txt")
        let axTextURL = captureURL.appendingPathComponent("accessibility_tree.txt")
        let axJSONURL = captureURL.appendingPathComponent("accessibility_tree.json")
        let appshotTextURL = captureURL.appendingPathComponent("appshot.md")
        let contextURL = captureURL.appendingPathComponent("context.json")
        let debugTextURL = captureURL.appendingPathComponent("debug.md")
        let captureMetricsURL = captureURL.appendingPathComponent("capture_metrics.json")
        let captureDiagnosticsURL = captureURL.appendingPathComponent("capture_diagnostics.json")
        let metadataURL = captureURL.appendingPathComponent("metadata.json")

        let copiedScreenshotURL = try measure("screenshot encode/write", using: metricsRecorder) {
            try copyScreenshotIfAvailable(
                sourcePath: metadata.screenshotPath,
                to: screenshotURL
            )
        }
        let copiedCaptureDiagnosticsURL = try copyCaptureDiagnosticsIfAvailable(
            sourcePath: metadata.screenshotPath,
            to: captureDiagnosticsURL
        )
        let storedOutput = outputWithLocalScreenshotPath(
            output,
            originalMetadata: metadata,
            copiedScreenshotURL: copiedScreenshotURL
        )
        let storedStructuredState = structuredState.map {
            structuredStateWithMetadata($0, metadata: storedOutput.metadata ?? metadata)
        }
        let renderedAppStateText: String
        if let storedStructuredState {
            renderedAppStateText = measure("AX render text", using: metricsRecorder) {
                AppshotSnapshotRenderer.render(state: storedStructuredState)
            }
        } else {
            renderedAppStateText = storedOutput.text
        }
        metricsRecorder?.setAXNodeCount(storedStructuredState?.nodes.count ?? metadata.nodeSignatures.count)

        try renderedAppStateText.write(to: axTextURL, atomically: true, encoding: .utf8)
        if let storedStructuredState {
            let data = try measure("structured JSON encode", using: metricsRecorder) {
                try jsonEncoder().encode(storedStructuredState)
            }
            try data.write(to: axJSONURL, options: .atomic)
        }
        let pageURL = extractPageURL(
            appName: appName,
            bundleID: bundleID,
            appStateText: renderedAppStateText,
            structuredState: storedStructuredState
        )
        if let pageURL {
            try pageURL.write(to: pageURLFileURL, atomically: true, encoding: .utf8)
        }

        // Render the polished transition-snapshot card beside the capture. Best-effort:
        // a render failure must never fail the capture, so it logs and falls back to nil.
        let transitionSnapshotURL = captureURL.appendingPathComponent("transition-snapshot.png")
        let transitionSnapshotPath: String?
        if let copiedScreenshotURL {
            transitionSnapshotPath = measure("transition snapshot render", using: metricsRecorder) {
                renderTransitionSnapshot(
                    screenshotURL: copiedScreenshotURL,
                    appName: appName,
                    bundleID: bundleID,
                    to: transitionSnapshotURL
                )
            }
        } else {
            transitionSnapshotPath = nil
        }

        let record = AppshotRecord(
            schemaVersion: 1,
            id: captureID,
            createdAt: metadata.createdAt,
            appName: appName,
            bundleID: bundleID,
            pid: metadata.pid,
            surface: AppshotCaptureSurface(rawValue: storedStructuredState?.surface ?? "window") ?? .window,
            windowTitle: metadata.windowTitle,
            windowID: metadata.windowID,
            nodeCount: storedStructuredState?.nodes.count ?? metadata.nodeSignatures.count,
            selectedTextLength: selectedTextLength(in: renderedAppStateText),
            windowFrame: metadata.windowFrame.cgRect,
            screenshotSize: metadata.screenshotSize?.cgSize,
            fingerprint: metadata.fingerprint,
            directoryPath: captureURL.path,
            screenshotPath: copiedScreenshotURL?.path,
            pageURL: pageURL,
            pageURLPath: pageURL == nil ? nil : pageURLFileURL.path,
            axTextPath: axTextURL.path,
            axJSONPath: storedStructuredState == nil ? nil : axJSONURL.path,
            appshotTextPath: appshotTextURL.path,
            debugTextPath: debugTextURL.path,
            captureDiagnosticsPath: copiedCaptureDiagnosticsURL?.path,
            captureMetricsPath: metricsRecorder == nil ? nil : captureMetricsURL.path,
            metadataPath: metadataURL.path,
            fileBaseName: fileBaseName,
            captureNumber: captureNumber,
            transitionSnapshotPath: transitionSnapshotPath
        )

        if let copiedScreenshotURL {
            let storedBytes = try? fileManager.attributesOfItem(atPath: copiedScreenshotURL.path)[.size] as? Int
            let diagnostics = copiedCaptureDiagnosticsURL.flatMap { try? decodeCaptureDiagnostics(at: $0) }
            metricsRecorder?.setScreenshot(
                backend: diagnostics?.backend,
                rawBytes: nil,
                storedBytes: storedBytes
            )
        }

        let appshotText = modelFacingAppshotText(record: record, appStateText: renderedAppStateText)
        let debugText = codexStyleAppshotText(record: record, appStateText: renderedAppStateText)
        try measure("final artifact write", using: metricsRecorder) {
            try appshotText.write(to: appshotTextURL, atomically: true, encoding: .utf8)
            try debugText.write(to: debugTextURL, atomically: true, encoding: .utf8)
            let contextData = try jsonEncoder().encode(
                try appshotContext(
                    for: record,
                    appStateText: renderedAppStateText,
                    includeImageData: false,
                    includeAppIconData: false
                )
            )
            try contextData.write(to: contextURL, options: .atomic)
            try writeMetadata(record)
        }
        try measure("index/latest update", using: metricsRecorder) {
            try updateIndex(with: record)
            try writeLatestPointers(record: record, appshotText: appshotText)
        }

        if let metricsRecorder {
            let data = try jsonEncoder().encode(metricsRecorder.snapshot())
            try data.write(to: captureMetricsURL, options: .atomic)
        }

        AppLog.store.notice("saved appshot id=\(record.id, privacy: .public) dir=\(captureURL.path, privacy: .public) screenshot=\(copiedScreenshotURL != nil, privacy: .public) nodes=\(record.nodeCount, privacy: .public)")
        return record
    }

    private func appStateText(for record: AppshotRecord) throws -> String {
        if let state = try structuredState(for: record) {
            return AppshotSnapshotRenderer.render(state: state)
        }
        return try String(contentsOf: record.axTextURL, encoding: .utf8)
    }

    private func structuredState(for record: AppshotRecord) throws -> CapturedAppState? {
        guard let axJSONURL = record.axJSONURL,
              fileManager.fileExists(atPath: axJSONURL.path)
        else {
            return nil
        }

        let data = try Data(contentsOf: axJSONURL)
        return try jsonDecoder().decode(CapturedAppState.self, from: data)
    }

    private func structuredStateWithMetadata(
        _ state: CapturedAppState,
        metadata: CaptureMetadata
    ) -> CapturedAppState {
        var updated = state
        updated.metadata = metadata
        return updated
    }

    private func copyScreenshotIfAvailable(
        sourcePath: String?,
        to destinationURL: URL
    ) throws -> URL? {
        guard let sourcePath,
              fileManager.fileExists(atPath: sourcePath)
        else {
            return nil
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        try copyReplacingItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func copyCaptureDiagnosticsIfAvailable(
        sourcePath: String?,
        to destinationURL: URL
    ) throws -> URL? {
        guard let sourcePath else {
            return nil
        }

        let sourceURL = BackgroundWindowCapture.diagnosticsURL(for: URL(fileURLWithPath: sourcePath))
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        try copyReplacingItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    /// Copies `sourceURL` to `destinationURL`, replacing any existing file there.
    private func copyReplacingItem(at sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func decodeCaptureDiagnostics(at url: URL) throws -> AppshotCaptureDiagnostics {
        let data = try Data(contentsOf: url)
        return try jsonDecoder().decode(AppshotCaptureDiagnostics.self, from: data)
    }

    private func transitionSnapshotHeight(for record: AppshotRecord) -> Double? {
        let style = AppshotTransitionSnapshotStyle.default

        // Prefer the rendered transition PNG's real display height (pixels -> points).
        if let transitionURL = record.transitionSnapshotURL,
           fileManager.fileExists(atPath: transitionURL.path),
           let pixelSize = pngPixelSize(at: transitionURL),
           pixelSize.height > 0 {
            return Double(pixelSize.height) / Double(style.defaultBackingScale)
        }

        guard let screenshotSize = record.screenshotSize,
              screenshotSize.width > 0,
              screenshotSize.height > 0
        else {
            return nil
        }

        return Self.transitionSnapshotDisplayWidth * Double(screenshotSize.height / screenshotSize.width)
    }

    /// Renders the polished transition-snapshot card via the pure CoreGraphics renderer.
    /// Best-effort: any failure is logged and surfaces as `nil` so the capture save never
    /// fails on a render error.
    private func renderTransitionSnapshot(
        screenshotURL: URL,
        appName: String,
        bundleID: String,
        to url: URL
    ) -> String? {
        let style = AppshotTransitionSnapshotStyle.default
        do {
            let snapshot = try AppshotTransitionSnapshotRenderer.render(
                screenshotURL: screenshotURL,
                appName: appName,
                appIcon: appIconCGImage(forBundleID: bundleID),
                backingScale: style.defaultBackingScale,
                style: style,
                to: url
            )
            return snapshot.url.path
        } catch {
            AppLog.store.error("transition snapshot render failed for app=\(appName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func pngPixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double
        else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private func nextCaptureNumber() -> Int {
        (loadIndex().map(\.captureNumber).max() ?? 0) + 1
    }

    private func captureID(fileBaseName: String, captureNumber: Int, date: Date) -> String {
        "\(timestampFolderName(for: date))-\(fileBaseName)-\(captureNumber)"
    }

    private func sanitizedFileBaseName(appName: String, bundleID: String) -> String {
        let readableName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = readableName.isEmpty ? fallbackName : readableName
        let disallowed = CharacterSet(charactersIn: "/:\u{0}\"")
            .union(.controlCharacters)
            .union(.newlines)
        let sanitizedScalars = rawName.unicodeScalars.map { scalar in
            disallowed.contains(scalar) ? "-" : String(scalar)
        }
        let sanitized = sanitizedScalars
            .joined()
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))

        return sanitized.isEmpty ? "appshot" : sanitized
    }

    private func outputWithLocalScreenshotPath(
        _ output: CaptureOutput,
        originalMetadata: CaptureMetadata,
        copiedScreenshotURL: URL?
    ) -> CaptureOutput {
        guard let copiedScreenshotURL else {
            return output
        }

        var metadata = originalMetadata
        var storedOutput = output
        let copiedPath = copiedScreenshotURL.path

        if let originalPath = originalMetadata.screenshotPath, originalPath != copiedPath {
            storedOutput.text = storedOutput.text.replacingOccurrences(
                of: originalPath,
                with: copiedPath
            )
        }

        metadata.screenshotPath = copiedPath
        storedOutput.metadata = metadata
        return storedOutput
    }

    private func writeMetadata(_ record: AppshotRecord) throws {
        let data = try jsonEncoder().encode(record)
        try data.write(to: record.metadataURL, options: .atomic)
    }

    private func writeLatestPointers(record: AppshotRecord, appshotText: String) throws {
        try record.directoryPath.write(to: latestTextURL, atomically: true, encoding: .utf8)
        try appshotText.write(to: latestPromptURL, atomically: true, encoding: .utf8)
        let data = try jsonEncoder().encode(record)
        try data.write(to: latestMetadataURL, options: .atomic)
    }

    private func updateIndex(with record: AppshotRecord) throws {
        var records = loadIndex()
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        let data = try jsonEncoder().encode(records)
        try data.write(to: indexURL, options: .atomic)
    }

    private func loadIndex() -> [AppshotRecord] {
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let records = try? jsonDecoder().decode([AppshotRecord].self, from: data)
        else {
            return []
        }
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    private func searchableText(for record: AppshotRecord) -> String {
        let fileText = [
            try? String(contentsOf: record.appshotTextURL, encoding: .utf8),
            try? String(contentsOf: record.axTextURL, encoding: .utf8),
        ].compactMap { $0 }.joined(separator: "\n")

        return [
            record.id,
            record.appName,
            record.bundleID,
            record.windowTitle,
            record.pageURL ?? "",
            record.directoryPath,
            fileText,
        ].joined(separator: "\n")
    }

    private func removeLatestPointers() throws {
        for url in [latestTextURL, latestPromptURL, latestMetadataURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Runs `body`, recording it as a timed phase when `recorder` is present and
    /// otherwise running it untimed. Collapses the `recorder?.measure { … } ?? …`
    /// pattern that would otherwise duplicate every measured body.
    private func measure<T>(
        _ name: String,
        using recorder: AppshotCaptureMetricsRecorder?,
        _ body: () throws -> T
    ) rethrows -> T {
        if let recorder {
            return try recorder.measure(name, body)
        }
        return try body()
    }

    private func jsonEncoder() -> JSONEncoder {
        AppshotJSON.encoder
    }

    private func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func selectedTextLength(in text: String) -> Int {
        guard let range = text.range(of: "Selected text: ```") else {
            return 0
        }
        let selectedBlock = text[range.upperBound...]
        guard let end = selectedBlock.range(of: "```") else {
            return selectedBlock.count
        }
        return selectedBlock[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).count
    }
}
