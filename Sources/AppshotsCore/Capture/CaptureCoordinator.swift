import Foundation

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
}
