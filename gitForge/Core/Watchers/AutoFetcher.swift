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
    private var fetchClosure: (@MainActor () async -> Void)?

    deinit { task?.cancel() }

    func start(intervalSeconds: Int, fetch: @escaping @MainActor () async -> Void) {
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
    }

    /// Cancels the loop but keeps the configuration so `resume()` can
    /// restart it on the same interval. Used when the app loses focus.
    func pause() {
        task?.cancel()
        task = nil
    }

    /// Restarts the loop if it had been paused (had an interval + closure).
    /// No-op if the fetcher was stopped or never configured.
    func resume() {
        guard task == nil, intervalSeconds > 0, fetchClosure != nil else { return }
        scheduleLoop()
    }

    private func scheduleLoop() {
        let seconds = intervalSeconds
        let fetch = fetchClosure
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, self != nil else { return }
                await fetch?()
            }
        }
    }
}
