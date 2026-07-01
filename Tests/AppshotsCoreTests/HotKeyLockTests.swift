@testable import AppshotsCore
import Foundation
import Testing

/// Covers the advisory exclusive ``HotKeyLock`` (FIX B regression). Two locks on
/// the same temp root contend over a single `hotkey.lock`; the real `~/.appshots`
/// is never touched.
struct HotKeyLockTests {
    @Test func `Second acquire is excluded until the first releases`() {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let first = HotKeyLock(rootURL: rootURL)
        let second = HotKeyLock(rootURL: rootURL)
        defer {
            first.release()
            second.release()
        }

        #expect(first.tryAcquire() == true)
        #expect(first.isHeld)
        // A second in-process holder on the same lock file is refused.
        #expect(second.tryAcquire() == false)
        #expect(second.isHeld == false)

        // Once the first releases, the lock becomes available again.
        first.release()
        #expect(first.isHeld == false)
        #expect(second.tryAcquire() == true)
        #expect(second.isHeld)
    }

    @Test func `Acquire is idempotent for the same instance`() {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let lock = HotKeyLock(rootURL: rootURL)
        defer { lock.release() }

        #expect(lock.tryAcquire() == true)
        #expect(lock.tryAcquire() == true)
        #expect(lock.isHeld)

        lock.release()
        #expect(lock.isHeld == false)
    }

    private func temporaryRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("appshots-hotkeylock-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
