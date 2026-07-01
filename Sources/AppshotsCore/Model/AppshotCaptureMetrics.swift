import Foundation

public struct CapturePhaseMetric: Codable, Equatable, Sendable {
    public var name: String
    public var startedAtOffsetMs: Double
    public var durationMs: Double
    public var detail: String?

    public init(
        name: String,
        startedAtOffsetMs: Double,
        durationMs: Double,
        detail: String? = nil
    ) {
        self.name = name
        self.startedAtOffsetMs = startedAtOffsetMs
        self.durationMs = durationMs
        self.detail = detail
    }
}

public struct AppshotCaptureMetrics: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestID: String
    public var coldStart: Bool
    public var startedAt: Date
    public var phases: [CapturePhaseMetric]
    public var axNodeCount: Int
    public var axCallsByKind: [String: Int]
    public var screenshotBackend: String?
    public var rawScreenshotBytes: Int?
    public var storedScreenshotBytes: Int?
    public var cacheHit: Bool?
    public var cacheReason: String?

    public init(
        schemaVersion: Int = 1,
        requestID: String,
        coldStart: Bool,
        startedAt: Date = Date(),
        phases: [CapturePhaseMetric] = [],
        axNodeCount: Int = 0,
        axCallsByKind: [String: Int] = [:],
        screenshotBackend: String? = nil,
        rawScreenshotBytes: Int? = nil,
        storedScreenshotBytes: Int? = nil,
        cacheHit: Bool? = nil,
        cacheReason: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.coldStart = coldStart
        self.startedAt = startedAt
        self.phases = phases
        self.axNodeCount = axNodeCount
        self.axCallsByKind = axCallsByKind
        self.screenshotBackend = screenshotBackend
        self.rawScreenshotBytes = rawScreenshotBytes
        self.storedScreenshotBytes = storedScreenshotBytes
        self.cacheHit = cacheHit
        self.cacheReason = cacheReason
    }
}

public enum AppshotCaptureSurface: String, Codable, Equatable, Sendable {
    case window
    case menu
    case status
    case textOnly
}

public final class AppshotCaptureMetricsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let monotonicStart = DispatchTime.now().uptimeNanoseconds
    private var metrics: AppshotCaptureMetrics

    public init(requestID: String, coldStart: Bool) {
        metrics = AppshotCaptureMetrics(requestID: requestID, coldStart: coldStart)
    }

    public func mark(_ name: String, detail: String? = nil) {
        recordPhase(name, started: DispatchTime.now().uptimeNanoseconds, ended: DispatchTime.now().uptimeNanoseconds, detail: detail)
    }

    @discardableResult
    public func measure<T>(_ name: String, detail: String? = nil, _ body: () throws -> T) rethrows -> T {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            recordPhase(name, started: started, ended: DispatchTime.now().uptimeNanoseconds, detail: detail)
        }
        return try body()
    }

    public func recordPhase(
        _ name: String,
        started: UInt64,
        ended: UInt64,
        detail: String? = nil
    ) {
        let startOffset = Double(started - monotonicStart) / 1_000_000
        let duration = Double(ended - started) / 1_000_000
        lock.withLock {
            metrics.phases.append(CapturePhaseMetric(
                name: name,
                startedAtOffsetMs: startOffset,
                durationMs: duration,
                detail: detail
            ))
        }
    }

    public func recordAXCall(kind: String) {
        lock.withLock {
            metrics.axCallsByKind[kind, default: 0] += 1
        }
    }

    public func setAXNodeCount(_ count: Int) {
        lock.withLock {
            metrics.axNodeCount = count
        }
    }

    public func setScreenshot(
        backend: String?,
        rawBytes: Int?,
        storedBytes: Int?
    ) {
        lock.withLock {
            metrics.screenshotBackend = backend ?? metrics.screenshotBackend
            metrics.rawScreenshotBytes = rawBytes ?? metrics.rawScreenshotBytes
            metrics.storedScreenshotBytes = storedBytes ?? metrics.storedScreenshotBytes
        }
    }

    public func setCache(hit: Bool, reason: String) {
        lock.withLock {
            metrics.cacheHit = hit
            metrics.cacheReason = reason
        }
    }

    public func snapshot() -> AppshotCaptureMetrics {
        lock.withLock { metrics }
    }
}

enum AppshotCaptureMetricsContext {
    private static let state = State()

    static func withRecorder<T>(
        _ recorder: AppshotCaptureMetricsRecorder?,
        _ body: () throws -> T
    ) rethrows -> T {
        state.set(recorder)
        defer { state.set(nil) }
        return try body()
    }

    static func mark(_ name: String, detail: String? = nil) {
        state.current?.mark(name, detail: detail)
    }

    static func measure<T>(_ name: String, detail: String? = nil, _ body: () throws -> T) rethrows -> T {
        guard let recorder = state.current else {
            return try body()
        }
        return try recorder.measure(name, detail: detail, body)
    }

    static func recordPhase(
        _ name: String,
        started: UInt64,
        ended: UInt64,
        detail: String? = nil
    ) {
        state.current?.recordPhase(name, started: started, ended: ended, detail: detail)
    }

    static func recordAXCall(kind: String) {
        state.current?.recordAXCall(kind: kind)
    }

    static func setAXNodeCount(_ count: Int) {
        state.current?.setAXNodeCount(count)
    }

    static func setScreenshot(backend: String?, rawBytes: Int?, storedBytes: Int?) {
        state.current?.setScreenshot(backend: backend, rawBytes: rawBytes, storedBytes: storedBytes)
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var recorder: AppshotCaptureMetricsRecorder?

        var current: AppshotCaptureMetricsRecorder? {
            lock.withLock { recorder }
        }

        func set(_ newValue: AppshotCaptureMetricsRecorder?) {
            lock.withLock {
                recorder = newValue
            }
        }
    }
}
