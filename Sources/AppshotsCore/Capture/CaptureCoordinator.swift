import Foundation

public struct CaptureCoordinatorSnapshot: Codable, Equatable, Sendable {
    public var activeRequestID: String?
    public var lastBundleID: String?
    public var lastPID: pid_t?
    public var lastWindowID: Int?
    public var lastWindowTitle: String?
    public var lastWindowFrame: CGRect?
    public var lastFingerprint: String?
}

public actor CaptureCoordinator {
    public static let shared = CaptureCoordinator()

    private var activeRequestID: String?
    private var lastTarget: FrontmostAppTarget?
    private var lastRecord: AppshotRecord?

    private init() {}

    public func prewarmGlobal() {
        do {
            try SnapshotCacheStore.ensureRootDirectory()
        } catch {
            AppLog.capture.debug("capture coordinator prewarm could not create snapshot cache: \(error.localizedDescription, privacy: .public)")
        }
        BackgroundWindowCapture.prewarm()
    }

    public func prewarm(target: FrontmostAppTarget) {
        lastTarget = target
        AccessibilityCaptureEngine.prewarm(pid: target.pid)
    }

    public func prewarm(pid: pid_t) {
        AccessibilityCaptureEngine.prewarm(pid: pid)
    }

    public func beginCapture(requestID: String, target: FrontmostAppTarget) -> String {
        activeRequestID = requestID
        defer {
            lastTarget = target
        }

        guard let lastTarget,
              let lastRecord,
              lastTarget.pid == target.pid,
              lastTarget.bundleID == target.bundleID
        else {
            return "target_cache_miss"
        }
        return "same_target window=\(lastRecord.windowID)"
    }

    public func completeCapture(requestID: String, record: AppshotRecord) {
        if activeRequestID == requestID {
            activeRequestID = nil
        }
        lastRecord = record
    }

    public func snapshot() -> CaptureCoordinatorSnapshot {
        CaptureCoordinatorSnapshot(
            activeRequestID: activeRequestID,
            lastBundleID: lastTarget?.bundleID,
            lastPID: lastTarget?.pid,
            lastWindowID: lastRecord?.windowID,
            lastWindowTitle: lastRecord?.windowTitle,
            lastWindowFrame: lastRecord?.windowFrame,
            lastFingerprint: lastRecord?.fingerprint
        )
    }
}
