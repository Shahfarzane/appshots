import Foundation

/// Cross-process advisory lock guaranteeing at most one process hosts the global
/// capture hot key at a time.
///
/// Both the menu-bar GUI and the headless `appshotsctl daemon` can arm an
/// `NSEvent` global monitor for the trigger chord; those monitors are
/// per-process and observe-only, so two armed monitors would both fire on the
/// same chord (a double capture). This lock — an exclusive, non-blocking
/// `flock` on `<AppshotStore root>/hotkey.lock` — lets whichever process owns
/// the hot key for the current `startupMode` claim it while the other backs off.
///
/// The retained fd keeps the lock held for as long as the instance lives;
/// ``release()`` (or `deinit`) drops it.
///
/// `@unchecked Sendable`: the mutable `fileDescriptor` is guarded by `lock`.
public final class HotKeyLock: @unchecked Sendable {
    private let lockURL: URL
    private let lock = NSLock()
    private var fileDescriptor: Int32 = -1

    /// Creates a lock backed by `hotkey.lock` under `rootURL` (defaults to the
    /// shared `~/.appshots` store root).
    public init(rootURL: URL? = nil) {
        let root = rootURL ??
            FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".appshots", isDirectory: true)
        lockURL = root.appendingPathComponent("hotkey.lock")
    }

    /// Attempts to take the exclusive, non-blocking hot-key lock, retaining the
    /// fd on success. Returns `false` (holding nothing) when another process
    /// already owns it or the lock file cannot be opened. Idempotent: returns
    /// `true` if this instance already holds the lock.
    @discardableResult
    public func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fileDescriptor >= 0 { return true }

        let directory = lockURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            AppLog.lifecycle.error("hot-key lock open failed at \(self.lockURL.path, privacy: .public)")
            return false
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        fileDescriptor = fd
        return true
    }

    /// Whether this instance currently holds the lock.
    public var isHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fileDescriptor >= 0
    }

    /// Releases the lock if held. Idempotent.
    public func release() {
        lock.lock()
        defer { lock.unlock() }
        guard fileDescriptor >= 0 else { return }
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }

    deinit {
        release()
    }
}
