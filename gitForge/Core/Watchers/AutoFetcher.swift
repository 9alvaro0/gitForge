import Foundation

/// Background timer that triggers `git fetch` periodically. Disabled by default
/// — `start` reads the interval from `gitForge.autoFetchInterval` (in seconds)
/// in the global config and only schedules if it's set and > 0.
@MainActor
final class AutoFetcher {
    private var task: Task<Void, Never>?
    private(set) var intervalSeconds: Int = 0
    /// Stored so `resume()` can reschedule without the caller re-supplying
    /// the closure. Cleared by `stop()`; preserved by `pause()`.
    private var fetchClosure: (@MainActor () async -> Bool)?
    /// Consecutive `fetch -> false` returns since the last success. Drives
    /// the offline backoff so we don't keep hammering the network with
    /// failing fetches every `intervalSeconds`.
    private var consecutiveFailures: Int = 0
    /// Cap on the backoff multiplier — even a long offline period should
    /// retry at most once per `cap * intervalSeconds`. 60× = 30 min at the
    /// default 30s interval, which feels right for "I'm on a plane".
    private static let backoffCap: Int = 60

    deinit { task?.cancel() }

    func start(intervalSeconds: Int, fetch: @escaping @MainActor () async -> Bool) {
        stop()
        self.intervalSeconds = intervalSeconds
        self.fetchClosure = fetch
        guard intervalSeconds > 0 else { return }
        scheduleLoop()
    }

    /// Cancels the loop and forgets the closure. Use when reactivity is
    /// being torn down for good (`stopReactivity()`).
    func stop() {
        task?.cancel()
        task = nil
        intervalSeconds = 0
        fetchClosure = nil
        consecutiveFailures = 0
    }

    /// Cancels the loop but keeps the configuration so `resume()` can
    /// restart it on the same interval. Used when the app loses focus.
    func pause() {
        task?.cancel()
        task = nil
    }

    /// Restarts the loop if it had been paused (had an interval + closure).
    /// No-op if the fetcher was stopped or never configured. Resumes from a
    /// clean backoff slate so coming back online retries promptly.
    func resume() {
        guard task == nil, intervalSeconds > 0, fetchClosure != nil else { return }
        consecutiveFailures = 0
        scheduleLoop()
    }

    /// Effective sleep before the next attempt, after the current failure
    /// count. Exposed for unit tests.
    static func backoffDelay(base intervalSeconds: Int, failures: Int) -> Int {
        guard intervalSeconds > 0 else { return 0 }
        // 2^failures, capped, so 0 → 1×, 1 → 2×, 2 → 4×, …
        let multiplier = min(1 << max(0, failures), backoffCap)
        return intervalSeconds * multiplier
    }

    private func scheduleLoop() {
        let base = intervalSeconds
        let fetch = fetchClosure
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let failures = self?.consecutiveFailures ?? 0
                let sleepFor = Self.backoffDelay(base: base, failures: failures)
                try? await Task.sleep(for: .seconds(sleepFor))
                guard !Task.isCancelled, let self else { return }
                let ok = await fetch?() ?? false
                guard !Task.isCancelled else { return }
                if ok {
                    self.consecutiveFailures = 0
                } else {
                    self.consecutiveFailures += 1
                }
            }
        }
    }
}
