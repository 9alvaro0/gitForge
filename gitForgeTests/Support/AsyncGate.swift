import Foundation

/// Holds async work until the test opens it. `wait()` suspends until
/// `open()`; `waiting()` returns once something is suspended in `wait()`.
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isWaiting: Bool { lock.withLock { !waiters.isEmpty } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let pending = lock.withLock {
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }

    /// Returns once a caller is suspended in `wait()` (or after `timeout`).
    func waiting(timeout: Duration = .seconds(3)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !isWaiting, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
