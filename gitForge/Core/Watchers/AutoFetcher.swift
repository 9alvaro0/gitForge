import Foundation

/// Background timer that triggers `git fetch` periodically. Disabled by default
/// — `start` reads the interval from `gitForge.autoFetchInterval` (in seconds)
/// in the global config and only schedules if it's set and > 0.
@MainActor
final class AutoFetcher {
    private var task: Task<Void, Never>?
    private(set) var intervalSeconds: Int = 0

    deinit { task?.cancel() }

    func start(intervalSeconds: Int, fetch: @escaping @MainActor () async -> Void) {
        stop()
        self.intervalSeconds = intervalSeconds
        guard intervalSeconds > 0 else { return }
        let seconds = intervalSeconds
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, self != nil else { return }
                await fetch()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        intervalSeconds = 0
    }
}
