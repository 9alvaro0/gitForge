import Foundation
import Testing

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

    /// Returns once a caller is suspended in `wait()`. If none gets there within
    /// `timeout` it records an issue and returns, so a slow run fails here and
    /// not on a later assertion that depended on the caller being suspended.
    /// The default is generous: it costs nothing when the caller gets there, and
    /// a busy machine running the whole suite can stall for several seconds.
    func waiting(timeout: Duration = .seconds(15), sourceLocation: SourceLocation = #_sourceLocation) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !isWaiting, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        if !isWaiting {
            Issue.record("No caller was suspended in the gate's wait() within \(timeout)", sourceLocation: sourceLocation)
        }
    }
}
