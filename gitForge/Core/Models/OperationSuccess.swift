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
        let message: String
        switch (amend, shortSha) {
        case (false, nil): message = String(localized: "Committed “\(subject)”")
        case (true, nil): message = String(localized: "Amended “\(subject)”")
        case (false, let sha?): message = String(localized: "Committed \(sha) — \(subject)")
        case (true, let sha?): message = String(localized: "Amended \(sha) — \(subject)")
        }
        return OperationSuccess(message: message)
    }

    /// `behind` is the count after the fetch; `upstream` nil means the
    /// branch tracks nothing, so there's nothing to compare against.
    static func fetch(upstream: String?, behind: Int) -> OperationSuccess {
        guard let upstream else { return OperationSuccess(message: String(localized: "Fetched")) }
        guard behind > 0 else {
            return OperationSuccess(message: String(localized: "Fetched — \(upstream) has nothing new"))
        }
        return OperationSuccess(message: behind == 1
            ? String(localized: "Fetched — 1 commit to pull from \(upstream)")
            : String(localized: "Fetched — \(behind) commits to pull from \(upstream)"))
    }

    static func pull(upstream: String?, changed: Bool) -> OperationSuccess {
        guard changed else { return OperationSuccess(message: String(localized: "Already up to date")) }
        guard let upstream else { return OperationSuccess(message: String(localized: "Pulled")) }
        return OperationSuccess(message: String(localized: "Pulled from \(upstream)"))
    }

    /// `ahead` is the count before the push. A first push (no upstream yet)
    /// has no count to report, so it names the new tracking branch instead.
    static func push(branch: String?, remote: String, ahead: Int,
                     firstPush: Bool, forced: Bool) -> OperationSuccess {
        let target = branch.map { "\(remote)/\($0)" } ?? remote
        if firstPush {
            let name = branch ?? String(localized: "branch")
            return OperationSuccess(message: String(localized: "Published \(name) to \(target)"))
        }
        let message: String
        switch (forced, ahead) {
        case (true, ...0): message = String(localized: "Force-pushed to \(target)")
        case (false, ...0): message = String(localized: "\(target) is already up to date")
        case (true, 1): message = String(localized: "Force-pushed 1 commit to \(target)")
        case (false, 1): message = String(localized: "Pushed 1 commit to \(target)")
        case (true, _): message = String(localized: "Force-pushed \(ahead) commits to \(target)")
        case (false, _): message = String(localized: "Pushed \(ahead) commits to \(target)")
        }
        return OperationSuccess(message: message)
    }
}
