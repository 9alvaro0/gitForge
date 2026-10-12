import Foundation

/// Tasks a repository session spawns from `didSet` reactions (commit / file
/// diff loads, amend prefill…). Shared by the view model and its stores so
/// `stopReactivity()` cancels all of them in one place — otherwise a slow
/// `git` lookup keeps the previous session alive for seconds after the user
/// opened another repo.
@MainActor
final class OwnedTasks {
    private(set) var tasks: [UUID: Task<Void, Never>] = [:]

    var isEmpty: Bool { tasks.isEmpty }
    var count: Int { tasks.count }

    /// Runs `operation` as an owned task. Each task removes itself when it
    /// finishes, so the registry only ever holds in-flight work.
    func track(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            await operation()
            self?.tasks[id] = nil
        }
    }

    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }
}
