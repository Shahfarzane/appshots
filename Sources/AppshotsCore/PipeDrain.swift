import Foundation

/// Accumulates one pipe of a child process off-thread so both of its pipes
/// drain concurrently. Reading stdout to EOF before touching stderr (or vice
/// versa) deadlocks as soon as the child fills the un-read pipe's kernel
/// buffer (~64KB) while the read one is still open.
///
/// `@unchecked Sendable`: the mutable buffer is guarded by `lock`; the
/// readability handler runs on FileHandle's own callback queue.
final class PipeDrain: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let finished = DispatchSemaphore(value: 0)

    /// Starts draining `fileHandle` immediately. The instance keeps itself
    /// alive via the readability handler until EOF.
    init(_ fileHandle: FileHandle) {
        fileHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self.finished.signal()
            } else {
                self.lock.lock()
                self.buffer.append(chunk)
                self.lock.unlock()
            }
        }
    }

    /// Blocks until the pipe reaches EOF, then returns everything read.
    func waitForData() -> Data {
        finished.wait()
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
