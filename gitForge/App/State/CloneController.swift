import Foundation

/// Manages the in-flight clone operation: state for the progress UI, the
/// underlying `Task`, and cancel/start lifecycle. The actual clone logic
/// (talking to git, opening the cloned repo, surfacing toasts) lives in
/// `AppState.runClone` because it touches multiple sub-stores; this store
/// just owns task ownership and progress state.
@Observable
@MainActor
final class CloneController {
    var cloneState: CloneState = .idle
    var isCloning: Bool { cloneState.isRunning }

    private var cloneTask: Task<Void, Never>?

    /// Cancels any in-flight task and starts a fresh one running `work`.
    /// Once `work` finishes, clears the task slot and snaps `cloneState`
    /// back to `.idle` — but only if we're still the active task, so a
    /// stale finish doesn't blow away the state of a newer start.
    func start(_ work: @escaping () async -> Void) {
        // A newer `start()` cancels the previous task before assigning its
        // own to `cloneTask`. The post-work block uses `Task.isCancelled`
        // (which refers to *this* task) to detect that case and skip
        // cleanup — comparing `Task` instances would mean capturing the
        // task var before its assignment, which Sendable doesn't allow.
        cloneTask?.cancel()
        cloneTask = Task { [weak self] in
            await work()
            guard let self, !Task.isCancelled else { return }
            self.cloneTask = nil
            if case .running = self.cloneState { self.cloneState = .idle }
        }
    }

    func cancel() {
        cloneTask?.cancel()
    }
}
