import Foundation

/// File-backed store for ``AppshotSettings``, the single source of truth shared
/// by the GUI app and the `appshotsctl` CLI. Settings live at
/// `<root>/config.json` (root defaults to `~/.appshots`, the same root as
/// ``AppshotStore``).
///
/// Reads tolerate a missing or corrupt file by returning ``AppshotSettings/defaults``.
/// Every successful ``save(_:)`` posts the Darwin notification
/// `ceo.nerd.appshots.settings.changed` so a separate process (e.g. the CLI
/// writing settings) can live-update a running GUI via ``observe(_:)``.
///
/// Cross-process consistency (GUI + CLI writing concurrently) comes from an
/// advisory `flock` on a sibling `<root>/config.lock` file held for the whole
/// load→mutate→save window — **not** from the `NSLock`. The `NSLock` only
/// serialises threads *within* a single process; it cannot stop a second
/// process from interleaving a read-modify-write. The two nest as NSLock (outer)
/// then flock (inner), always in that order.
///
/// `@unchecked Sendable`: the only stored state is an immutable `rootURL` plus an
/// `NSLock` that serialises intra-process file access.
public final class AppshotSettingsStore: @unchecked Sendable {
    /// Darwin notification posted on every successful save.
    public static let changedNotificationName = "ceo.nerd.appshots.settings.changed"

    private let customRootURL: URL?
    private let lock = NSLock()

    public init(rootURL: URL? = nil) {
        customRootURL = rootURL
    }

    /// The settings root directory (defaults to `~/.appshots`, matching ``AppshotStore``).
    public var rootURL: URL {
        customRootURL ??
            FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".appshots", isDirectory: true)
    }

    /// The on-disk settings file.
    public var configURL: URL {
        rootURL.appendingPathComponent("config.json")
    }

    /// Whether a `config.json` already exists.
    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    /// Loads the persisted settings, returning ``AppshotSettings/defaults`` when
    /// the file is missing or cannot be decoded.
    public func load() -> AppshotSettings {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    /// Atomically writes `settings` to `config.json` and posts the change notification.
    public func save(_ settings: AppshotSettings) throws {
        lock.lock()
        defer { lock.unlock() }
        try withFileLock {
            try saveLocked(settings)
        }
    }

    /// Writes `settings` only when no `config.json` exists yet, keeping the
    /// existence check and the write inside one cross-process critical section
    /// so a concurrent `save`/`mutate` from another process (e.g. a CLI
    /// `config set` racing first GUI launch) can never be overwritten by the
    /// seed. Returns whether the seed was written.
    @discardableResult
    public func seedIfAbsent(_ settings: AppshotSettings) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return try withFileLock {
            guard FileManager.default.fileExists(atPath: configURL.path) == false else {
                return false
            }
            try saveLocked(settings)
            return true
        }
    }

    /// Loads, mutates, and saves the settings under a single lock (intra-process
    /// `NSLock` + cross-process `flock`) so concurrent callers — including a
    /// separate GUI / CLI process — cannot lose each other's writes.
    public func mutate(_ body: (inout AppshotSettings) throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        try withFileLock {
            var settings = loadLocked()
            try body(&settings)
            try saveLocked(settings)
        }
    }

    // MARK: - Cross-process file lock

    /// Runs `body` while holding an exclusive advisory lock on a sibling
    /// `<root>/config.lock` file, so a concurrent process cannot interleave its
    /// own read-modify-write. A **fresh** fd is opened (and closed) per call so
    /// the lock is never held re-entrantly across nested critical sections, and
    /// `flock(LOCK_EX)` blocks until any other process releases its lock. If the
    /// lock file cannot be opened, `body` still runs (degrading to the
    /// intra-process `NSLock` only) rather than failing the whole operation.
    private func withFileLock<T>(_ body: () throws -> T) rethrows -> T {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let lockURL = rootURL.appendingPathComponent("config.lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            AppLog.store.error("settings lock open failed at \(lockURL.path, privacy: .public); proceeding without cross-process lock")
            return try body()
        }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    // MARK: - Lock-held primitives

    private func loadLocked() -> AppshotSettings {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .defaults
        }
        do {
            let data = try Data(contentsOf: configURL)
            return try AppshotJSON.decoder.decode(AppshotSettings.self, from: data)
        } catch {
            AppLog.store.error("settings load failed, using defaults: \(error.localizedDescription, privacy: .public)")
            return .defaults
        }
    }

    private func saveLocked(_ settings: AppshotSettings) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try AppshotJSON.encoder.encode(settings)
        try data.write(to: configURL, options: .atomic)
        AppshotSettingsStore.postChangeNotification()
    }

    // MARK: - Darwin notification bridge

    private static func postChangeNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(changedNotificationName as CFString),
            nil,
            nil,
            true
        )
    }

    /// Registers a cross-process observer for settings changes. `handler` is
    /// invoked (on a CoreFoundation-driven callback) whenever any process saves
    /// settings; callers should hop to their own actor before touching state.
    /// Retain the returned token for as long as observation is wanted — releasing
    /// it (or calling ``AppshotSettingsObservationToken/cancel()``) deregisters.
    public static func observe(_ handler: @escaping @Sendable () -> Void) -> AppshotSettingsObservationToken {
        let box = SettingsObserverBox(handler: handler)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(box).toOpaque(),
            settingsChangedDarwinCallback,
            changedNotificationName as CFString,
            nil,
            .deliverImmediately
        )
        return AppshotSettingsObservationToken(box: box)
    }
}

/// Holds the `@Sendable` handler behind the opaque pointer handed to the C
/// notification callback. Kept alive by ``AppshotSettingsObservationToken``.
final class SettingsObserverBox {
    let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }
}

/// Opaque handle for an active settings observation. Deregisters on `cancel()`
/// or deinit. `@unchecked Sendable`: guards its mutable `cancelled` flag with a lock.
public final class AppshotSettingsObservationToken: @unchecked Sendable {
    private let box: SettingsObserverBox
    private let lock = NSLock()
    private var cancelled = false

    init(box: SettingsObserverBox) {
        self.box = box
    }

    /// Stops delivering change notifications to the handler. Idempotent.
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard cancelled == false else { return }
        cancelled = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(
            center,
            Unmanaged.passUnretained(box).toOpaque(),
            CFNotificationName(AppshotSettingsStore.changedNotificationName as CFString),
            nil
        )
    }

    deinit {
        cancel()
    }
}

/// C-convention callback for the Darwin notify center. Recovers the boxed
/// handler from the observer pointer and invokes it.
private func settingsChangedDarwinCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    let box = Unmanaged<SettingsObserverBox>.fromOpaque(observer).takeUnretainedValue()
    box.handler()
}
