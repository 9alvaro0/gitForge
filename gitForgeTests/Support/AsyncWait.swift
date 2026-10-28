import Foundation
import Testing

/// Polls `condition` on the main actor until it holds or `timeout` passes.
/// It returns as soon as the condition holds, so the generous default only
/// costs time when a test is failing anyway: on a loaded CI runner (the
/// whole suite runs in parallel) 3 s wasn't enough for the device flow
/// tests' stub-server round trips, and 15 s wasn't enough for a Reviews
/// refresh to reach its first reads.
@MainActor
func waitUntil(timeout: Duration = .seconds(60), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// `task`'s value once it finishes, woken by the task itself rather than by
/// polling. If it hasn't finished within `timeout` this records an issue and
/// returns nil, so a test that expects an answer while other work is held
/// fails here instead of hanging on `task.value`.
///
/// As with `AsyncGate.waiting(timeout:)`, `timeout` bounds a task that never
/// finishes, not a slow one: on a busy CI runner a 2 s deadline isn't enough.
@discardableResult
func finished<T: Sendable>(_ task: Task<T, Never>, timeout: Duration = .seconds(300),
                           sourceLocation: SourceLocation = #_sourceLocation) async -> T? {
    let first = FirstOutcome<T>()
    Task { first.offer(.finished(await task.value)) }
    let timer = Task {
        try? await Task.sleep(for: timeout)
        first.offer(.timedOut)
    }
    let outcome = await first.value()
    timer.cancel()
    switch outcome {
    case .finished(let value):
        return value
    case .timedOut:
        Issue.record("The task didn't finish within \(timeout)", sourceLocation: sourceLocation)
        return nil
    }
}

/// The first of several outcomes offered from any thread; later ones are
/// dropped. `value()` may start before or after the first offer.
private final class FirstOutcome<T: Sendable>: @unchecked Sendable {
    enum Outcome: Sendable {
        case finished(T)
        case timedOut
    }

    private let lock = NSLock()
    private var outcome: Outcome?
    private var waiter: CheckedContinuation<Outcome, Never>?

    func offer(_ offered: Outcome) {
        let resume: CheckedContinuation<Outcome, Never>? = lock.withLock {
            guard outcome == nil else { return nil }
            outcome = offered
            defer { waiter = nil }
            return waiter
        }
        resume?.resume(returning: offered)
    }

    func value() async -> Outcome {
        await withCheckedContinuation { continuation in
            let ready: Outcome? = lock.withLock {
                if let outcome { return outcome }
                waiter = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }
}
