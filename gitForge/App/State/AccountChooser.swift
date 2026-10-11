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

    func choose(_ remote: AmbiguousRemote) async -> RepoAccountChoice? {
        let request = Request(remote: remote)
        return await withCheckedContinuation { continuation in
            if waiters[request.key] != nil {
                waiters[request.key, default: []].append(continuation)
                return
            }
            waiters[request.key] = [continuation]
            queue.append(request)
            showNext()
        }
    }

    /// The sheet's answer; `nil` = Cancel (or the sheet went away).
    func answer(_ choice: RepoAccountChoice?) {
        guard let current = request else { return }
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
