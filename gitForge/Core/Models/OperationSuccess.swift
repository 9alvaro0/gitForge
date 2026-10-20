import Foundation

/// A commit / fetch / pull / push that finished cleanly, for the success
/// toast. The view model publishes it; `ShellView` turns it into a toast,
/// so every entry point (toolbar, menu, palette, commit box) gets the same
/// feedback. The `id` makes two identical successes in a row still register
/// as a change.
nonisolated struct OperationSuccess: Sendable, Equatable, Identifiable {
    let id = UUID()
    let message: String

    static func commit(shortSha: String?, subject: String, amend: Bool) -> OperationSuccess {
        let verb = amend ? "Amended" : "Committed"
        guard let shortSha else { return OperationSuccess(message: "\(verb) “\(subject)”") }
        return OperationSuccess(message: "\(verb) \(shortSha) — \(subject)")
    }

    /// `behind` is the count after the fetch; `upstream` nil means the
    /// branch tracks nothing, so there's nothing to compare against.
    static func fetch(upstream: String?, behind: Int) -> OperationSuccess {
        guard let upstream else { return OperationSuccess(message: "Fetched") }
        guard behind > 0 else { return OperationSuccess(message: "Fetched — \(upstream) has nothing new") }
        return OperationSuccess(message: "Fetched — \(commits(behind)) to pull from \(upstream)")
    }

    static func pull(upstream: String?, changed: Bool) -> OperationSuccess {
        guard changed else { return OperationSuccess(message: "Already up to date") }
        guard let upstream else { return OperationSuccess(message: "Pulled") }
        return OperationSuccess(message: "Pulled from \(upstream)")
    }

    /// `ahead` is the count before the push. A first push (no upstream yet)
    /// has no count to report, so it names the new tracking branch instead.
    static func push(branch: String?, remote: String, ahead: Int,
                     firstPush: Bool, forced: Bool) -> OperationSuccess {
        let verb = forced ? "Force-pushed" : "Pushed"
        let target = branch.map { "\(remote)/\($0)" } ?? remote
        if firstPush { return OperationSuccess(message: "Published \(branch ?? "branch") to \(target)") }
        guard ahead > 0 else {
            return OperationSuccess(message: forced ? "\(verb) to \(target)" : "\(target) is already up to date")
        }
        return OperationSuccess(message: "\(verb) \(commits(ahead)) to \(target)")
    }

    private static func commits(_ n: Int) -> String {
        n == 1 ? "1 commit" : "\(n) commits"
    }
}
