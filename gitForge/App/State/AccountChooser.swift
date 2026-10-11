import Foundation
import Observation

/// Asks which account a remote should use (P4 spec §4.2, §5.5): one sheet at
/// a time; operations asking about the same repo remote share its answer.
@MainActor
@Observable
final class AccountChooser {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let remote: AmbiguousRemote
        var key: String { remote.repoPath + "\u{0}" + remote.remoteName }
    }

    /// The sheet on screen, if any.
    private(set) var request: Request?
    @ObservationIgnored private var queue: [Request] = []
    @ObservationIgnored private var waiters: [String: [CheckedContinuation<RepoAccountChoice?, Never>]] = [:]

    /// `nil` = Cancel. A cancelled caller stops waiting (and its sheet goes
    /// away), so a clone or fetch can be cancelled while it asks.
    func choose(_ remote: AmbiguousRemote) async -> RepoAccountChoice? {
        let request = Request(remote: remote)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if waiters[request.key] != nil {
                    waiters[request.key, default: []].append(continuation)
                } else {
                    waiters[request.key] = [continuation]
                    queue.append(request)
                    showNext()
                }
                if Task.isCancelled { cancel(key: request.key) }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(key: request.key) }
        }
    }

    /// Answers `nil` to everyone waiting on `key`, shown or still queued.
    private func cancel(key: String) {
        if let current = request, current.key == key {
            answer(nil, for: current.id)
            return
        }
        queue.removeAll { $0.key == key }
        for continuation in waiters.removeValue(forKey: key) ?? [] { continuation.resume(returning: nil) }
    }

    /// The answer for the sheet showing `id`; `nil` = Cancel (or the sheet
    /// went away). A late answer for a sheet that's no longer shown is
    /// ignored, so it can't cancel the next one.
    func answer(_ choice: RepoAccountChoice?, for id: UUID) {
        guard let current = request, current.id == id else { return }
        let pending = waiters.removeValue(forKey: current.key) ?? []
        request = nil
        for continuation in pending { continuation.resume(returning: choice) }
        showNext()
    }

    private func showNext() {
        guard request == nil, !queue.isEmpty else { return }
        request = queue.removeFirst()
    }
}
