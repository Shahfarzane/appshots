import AppKit
import ApplicationServices
import Foundation

public struct FrontmostAppTarget: Equatable, Sendable {
    public var name: String
    public var bundleID: String
    public var pid: pid_t

    public init(name: String, bundleID: String, pid: pid_t) {
        self.name = name
        self.bundleID = bundleID
        self.pid = pid
    }
}

public enum AppshotCaptureService {
    /// Warms process-wide capture dependencies that are otherwise initialized on the first user
    /// capture: temp snapshot storage and ScreenCaptureKit shareable-content discovery.
    public static func prewarm() {
        do {
            try SnapshotCacheStore.ensureRootDirectory()
        } catch {
            AppLog.capture.debug("capture prewarm could not create snapshot cache: \(error.localizedDescription, privacy: .public)")
        }
        BackgroundWindowCapture.prewarm()
        Task.detached(priority: .utility) {
            await CaptureCoordinator.shared.prewarmGlobal()
        }
    }

    /// Warms a target app's accessibility tree in the background (AX connection + enhanced-UI
    /// rebuild) so the first capture of that app is as fast as subsequent ones. Call when the app
    /// becomes frontmost. Idempotent and off-main.
    public static func prewarm(pid: pid_t) {
        prewarm()
        AccessibilityCaptureEngine.prewarm(pid: pid)
        Task.detached(priority: .utility) {
            await CaptureCoordinator.shared.prewarm(pid: pid)
        }
    }

    public static func captureWithEvents(target: FrontmostAppTarget) throws -> [AppshotCaptureEvent] {
        var events: [AppshotCaptureEvent] = []
        _ = try captureWithEventHandler(target: target) { event in
            events.append(event)
        }
        return events
    }

    @discardableResult
    public static func captureWithEventHandler(
        target: FrontmostAppTarget,
        onEvent: @escaping (AppshotCaptureEvent) -> Void
    ) throws -> AppshotRecord {
        let requestID = UUID().uuidString
        var events: [AppshotCaptureEvent] = []
        let eventsLock = NSLock()
        func emit(_ event: AppshotCaptureEvent) {
            eventsLock.withLock {
                events.append(event)
            }
            onEvent(event)
        }

        AppLog.capture.notice("capture started request=\(requestID, privacy: .public) app=\(target.name, privacy: .public) bundle=\(target.bundleID, privacy: .public) pid=\(target.pid, privacy: .public)")
        let metricsRecorder = AppshotCaptureMetricsRecorder(requestID: requestID, coldStart: false)
        metricsRecorder.mark("hotkey received")
        emit(AppshotCaptureEvent(status: .started, requestID: requestID))
        let grantState = metricsRecorder.measure("permission check") {
            permissionGrantState()
        }
        if grantState != "both_granted" {
            AppLog.permissions.warning("capture permissions pending request=\(requestID, privacy: .public) state=\(grantState, privacy: .public)")
            emit(AppshotCaptureEvent(
                status: .permissionsPending,
                requestID: requestID,
                permissionGrantState: grantState
            ))
        }

        do {
            let record = try capture(
                target: target,
                requestID: requestID,
                metricsRecorder: metricsRecorder,
                onPartialEvent: emit
            )
            if record.screenshotPath != nil {
                if eventsLock.withLock({ events.contains(where: { $0.status == .screenshot }) }) == false {
                    emit(AppshotCaptureEvent(status: .screenshot, requestID: requestID, record: record))
                }
            } else if record.surface == .window {
                AppLog.capture.error("capture completed without screenshot request=\(requestID, privacy: .public) id=\(record.id, privacy: .public)")
                emit(AppshotCaptureEvent(
                    status: .failed,
                    requestID: requestID,
                    failureReason: "completed_without_screenshot",
                    record: record
                ))
                throw AppshotCaptureEventError(
                    events: eventsLock.withLock { events },
                    underlyingError: AppshotCaptureError.completedWithoutScreenshot(record.id)
                )
            } else {
                AppLog.capture.notice("capture completed as text-only surface request=\(requestID, privacy: .public) id=\(record.id, privacy: .public) surface=\(record.surface.rawValue, privacy: .public)")
            }
            var completed = try AppshotStore().completedEvent(for: record, requestID: requestID, includeImageData: false)
            completed.metrics = try? AppshotStore().captureMetrics(for: record)
            emit(completed)
            return record
        } catch let error as AppshotCaptureEventError {
            throw error
        } catch {
            AppLog.capture.error("capture failed request=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            emit(AppshotCaptureEvent(status: .failed, requestID: requestID, failureReason: error.localizedDescription))
            throw AppshotCaptureEventError(events: eventsLock.withLock { events }, underlyingError: error)
        }
    }

    public static func capture(target: FrontmostAppTarget) throws -> AppshotRecord {
        let requestID = UUID().uuidString
        let metricsRecorder = AppshotCaptureMetricsRecorder(requestID: requestID, coldStart: false)
        metricsRecorder.mark("hotkey received")
        _ = metricsRecorder.measure("permission check") {
            permissionGrantState()
        }
        return try capture(target: target, requestID: requestID, metricsRecorder: metricsRecorder)
    }

    public static func resolveTarget(matching identifier: String) throws -> FrontmostAppTarget {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedIdentifier.isEmpty == false else {
            throw CaptureError.invalidArgument("--app requires a bundle identifier or application name")
        }
        guard let app = AccessibilityCaptureEngine.resolveRunningApplicationIfAvailable(matching: trimmedIdentifier),
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy != .prohibited
        else {
            throw CaptureError.appNotRunning(trimmedIdentifier)
        }

        return FrontmostAppTarget(
            name: app.localizedName ?? app.bundleIdentifier ?? trimmedIdentifier,
            bundleID: app.bundleIdentifier ?? "",
            pid: app.processIdentifier
        )
    }

    private static func capture(
        target: FrontmostAppTarget,
        requestID: String,
        metricsRecorder: AppshotCaptureMetricsRecorder?,
        onPartialEvent: ((AppshotCaptureEvent) -> Void)? = nil
    ) throws -> AppshotRecord {
        let client = AppSnapshotCapturer(screenshotCompression: .appshotStored)
        defer { client.finish() }

        let appIdentifier = target.bundleID.isEmpty ? target.name : target.bundleID
        let started = DispatchTime.now()
        AppLog.capture.notice("capture begin app=\(appIdentifier, privacy: .public) pid=\(target.pid, privacy: .public)")

        let captured = try AppshotCaptureMetricsContext.withRecorder(metricsRecorder) {
            metricsRecorder?.mark("frontmost target resolve", detail: "\(target.bundleID):\(target.pid)")
            let cacheReason = beginCoordinatorCapture(requestID: requestID, target: target)
            metricsRecorder?.setCache(hit: cacheReason.hasPrefix("same_target"), reason: cacheReason)
            let eventEmitter = onPartialEvent.map(CaptureEventEmitter.init)
            let eventSink = eventEmitter.map { emitter in
                CaptureEventSink(
                    metadataResolved: { metadata in
                        emitter.emit(AppshotCaptureEvent(
                            status: .metadata,
                            requestID: requestID,
                            surface: metadata.surface,
                            windowID: metadata.windowID,
                            windowTitle: metadata.windowTitle,
                            windowFrame: metadata.windowFrame
                        ))
                    },
                    screenshotCaptured: { screenshot in
                        emitter.emit(AppshotCaptureEvent(
                            status: .screenshot,
                            requestID: requestID,
                            windowID: screenshot.windowID,
                            screenshotPath: screenshot.url.path,
                            screenshotSize: screenshot.size
                        ))
                    }
                )
            }
            // A single accessibility-tree walk yields both the formatted output
            // (for screenshot + metadata) and the structured state (rendered into
            // the stored appshot).
            return try client.appStateWithStructured(
                app: appIdentifier,
                includeScreenshot: true,
                options: CaptureOptions(
                    filterVisibleNodes: true,
                    includeElementIndexes: false,
                    preserveTextAreaNewlines: true
                ),
                eventSink: eventSink
            )
        }
        onPartialEvent?(AppshotCaptureEvent(
            status: .axText,
            requestID: requestID,
            axNodeCount: captured.state.nodes.count
        ))
        let snapshotMs = (DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000

        do {
            let record = try AppshotStore().save(
                target: target,
                output: captured.output,
                structuredState: captured.state,
                metricsRecorder: metricsRecorder
            )
            let totalMs = (DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
            AppLog.capture.notice("capture saved request=\(requestID, privacy: .public) id=\(record.id, privacy: .public) screenshot=\(record.screenshotPath ?? "none", privacy: .public) nodes=\(record.nodeCount, privacy: .public) snapshotMs=\(snapshotMs, privacy: .public) totalMs=\(totalMs, privacy: .public)")
            Task.detached(priority: .utility) {
                await CaptureCoordinator.shared.completeCapture(requestID: requestID, record: record)
            }
            return record
        } catch {
            AppLog.capture.error("capture save failed app=\(appIdentifier, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public static func captureFrontmostApplication() throws -> AppshotRecord {
        let target = try resolveFrontmostTarget()
        return try capture(target: target)
    }

    public static func captureFrontmostApplicationWithEvents() throws -> [AppshotCaptureEvent] {
        let target = try resolveFrontmostTarget()
        return try captureWithEvents(target: target)
    }

    @discardableResult
    public static func captureFrontmostApplicationWithEventHandler(
        onEvent: @escaping (AppshotCaptureEvent) -> Void
    ) throws -> AppshotRecord {
        let target = try resolveFrontmostTarget()
        return try captureWithEventHandler(target: target, onEvent: onEvent)
    }

    private static func resolveFrontmostTarget() throws -> FrontmostAppTarget {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy != .prohibited
        else {
            throw AppshotCaptureError.noFrontmostApplication
        }

        return FrontmostAppTarget(
            name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
            bundleID: app.bundleIdentifier ?? "",
            pid: app.processIdentifier
        )
    }

    private static func permissionGrantState() -> String {
        switch (AXIsProcessTrusted(), CGPreflightScreenCaptureAccess()) {
        case (true, true):
            return "both_granted"
        case (true, false):
            return "accessibility_granted"
        case (false, true):
            return "screen_recording_granted"
        case (false, false):
            return "none_granted"
        }
    }

    private static func beginCoordinatorCapture(requestID: String, target: FrontmostAppTarget) -> String {
        let box = CoordinatorReasonBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .utility) {
            let reason = await CaptureCoordinator.shared.beginCapture(requestID: requestID, target: target)
            box.set(reason)
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 0.25) == .timedOut {
            return "coordinator_timeout"
        }
        return box.value
    }
}

public enum AppshotCaptureError: LocalizedError {
    case noFrontmostApplication
    case completedWithoutScreenshot(String)

    public var errorDescription: String? {
        switch self {
        case .noFrontmostApplication:
            return "No frontmost application is available to capture."
        case .completedWithoutScreenshot(let id):
            return "Appshot capture completed without a screenshot: \(id)."
        }
    }
}

public struct AppshotCaptureEventError: LocalizedError {
    public var events: [AppshotCaptureEvent]
    public var underlyingError: Error

    public var errorDescription: String? {
        underlyingError.localizedDescription
    }
}

private final class CaptureEventEmitter: @unchecked Sendable {
    private let handler: (AppshotCaptureEvent) -> Void

    init(_ handler: @escaping (AppshotCaptureEvent) -> Void) {
        self.handler = handler
    }

    func emit(_ event: AppshotCaptureEvent) {
        handler(event)
    }
}

private final class CoordinatorReasonBox: @unchecked Sendable {
    private let lock = NSLock()
    private var reason = "target_cache_miss"

    var value: String {
        lock.withLock { reason }
    }

    func set(_ reason: String) {
        lock.withLock {
            self.reason = reason
        }
    }
}
