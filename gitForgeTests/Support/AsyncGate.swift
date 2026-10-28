import Foundation
import Testing

/// Holds async work until the test opens it. `wait()` suspends until
/// `open()`; `waiting()` returns once something is suspended in `wait()`.
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// `waiting()` calls to resume when a caller gets suspended in `wait()`.
    private var watchers: [UUID: CheckedContinuation<Void, Never>] = [:]

    var isWaiting: Bool { lock.withLock { !waiters.isEmpty } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let (resumeNow, arrived) = lock.withLock {
                if isOpen { return (true, [CheckedContinuation<Void, Never>]()) }
                waiters.append(continuation)
                defer { watchers = [:] }
                return (false, Array(watchers.values))
            }
            if resumeNow { continuation.resume() }
            arrived.forEach { $0.resume() }
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

    /// Returns once a caller is suspended in `wait()`, woken by that `wait()`
    /// itself rather than by polling. If none gets there within `timeout` it
    /// records an issue and returns, so a caller that never arrives fails
    /// here and not on a later assertion that depended on it being suspended.
    ///
    /// `timeout` bounds a caller that never arrives, not a slow one: a 15 s
    /// deadline failed on CI, where the whole suite keeps a small runner's
    /// threads busy and a Reviews refresh took longer than that to reach its
    /// first read. So the default outlasts the whole suite on CI.
    func waiting(timeout: Duration = .seconds(300), sourceLocation: SourceLocation = #_sourceLocation) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.untilACallerWaits() }
            group.addTask { try? await Task.sleep(for: timeout) }
            _ = await group.next()
            group.cancelAll()
        }
        if !isWaiting {
            Issue.record("No caller was suspended in the gate's wait() within \(timeout)", sourceLocation: sourceLocation)
        }
    }

    /// Returns once a caller is suspended in `wait()`, or once cancelled.
    private func untilACallerWaits() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeNow = lock.withLock {
                    if !waiters.isEmpty || Task.isCancelled { return true }
                    watchers[id] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            lock.withLock { watchers.removeValue(forKey: id) }?.resume()
        }
    }
}
