import Foundation

/// A commit (or the `--continue` of a merge / rebase / cherry-pick / revert)
/// that a local git hook stopped. Shown in a sheet with the hook's full
/// output instead of a one-line error, with Retry and — for a plain commit
/// only — "Commit without hooks" (#58).
nonisolated struct HookFailure: Sendable, Equatable, Identifiable {
    enum Operation: Sendable, Equatable {
        /// `pushAfterwards`: started from "Commit & push", so a successful
        /// retry pushes too. `confirmedAmendOfPublished`: the user already
        /// confirmed amending pushed history; a retry doesn't ask again.
        case commit(pushAfterwards: Bool, confirmedAmendOfPublished: Bool)
        case continueIntegration(MergeState)
    }

    /// Hooks that can stop a commit. `post-commit` can't: it runs after.
    static let commitHooks = ["pre-commit", "pre-merge-commit", "prepare-commit-msg", "commit-msg"]

    let id: UUID
    let operation: Operation
    /// The hook that failed, when the output or the installed hooks tell.
    let hookName: String?
    /// Everything the command printed. git sends a hook's stdout to stderr,
    /// so stderr holds both streams of the hook.
    let output: String

    init(id: UUID = UUID(), operation: Operation, hookName: String?, output: String) {
        self.id = id
        self.operation = operation
        self.hookName = hookName
        self.output = output
    }

    /// A hook failure for `stderr` of a failed commit / continue, or `nil`
    /// when no hook that could stop it is installed or the failure is git's
    /// own (nothing staged, unresolved conflicts, a lock file…). git prints
    /// nothing of its own when a hook fails, so installed hooks are the signal.
    init?(stderr: String, operation: Operation, installedHooks: [String]) {
        guard !installedHooks.isEmpty, !Self.isGitOwnFailure(stderr) else { return nil }
        self.init(operation: operation,
                  hookName: Self.hookName(in: stderr, installed: installedHooks),
                  output: GitCLI.redacted(stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// Only a plain commit can skip hooks: `--continue` has no `--no-verify`.
    var canSkipHooks: Bool {
        if case .commit = operation { return true }
        return false
    }

    var title: String {
        if let hookName { return String(localized: "The \(hookName) hook failed") }
        return String(localized: "A Git hook failed")
    }

    /// Whole sentences per case so translations can reorder freely.
    var message: String {
        switch operation {
        case .commit:
            return String(localized: "Nothing was committed. Your message and staged changes are kept: fix what the hook reports, then retry.")
        case .continueIntegration(.rebasing):
            return String(localized: "The rebase is still paused. Fix what the hook reports, then retry.")
        case .continueIntegration(.cherryPicking):
            return String(localized: "The cherry-pick is still paused. Fix what the hook reports, then retry.")
        case .continueIntegration(.reverting):
            return String(localized: "The revert is still paused. Fix what the hook reports, then retry.")
        case .continueIntegration:
            return String(localized: "The merge is still paused. Fix what the hook reports, then retry.")
        }
    }

    /// Short line left under the composer once the sheet is closed.
    var summary: String {
        if let hookName { return String(localized: "The \(hookName) hook failed. Nothing was committed.") }
        return String(localized: "A Git hook failed. Nothing was committed.")
    }

    /// The hook named in `output` (husky, lefthook and pre-commit print it),
    /// else the only installed one. A name only counts as a whole word, so
    /// `commit-msg` isn't read inside `prepare-commit-msg`.
    static func hookName(in output: String, installed: [String]) -> String? {
        let byLength = installed.sorted { $0.count > $1.count }
        for name in byLength {
            let pattern = "(?<![\\w-])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\w-])"
            if output.range(of: pattern, options: .regularExpression) != nil { return name }
        }
        return installed.count == 1 ? installed[0] : nil
    }

    /// Failures git reports itself, before or instead of a hook.
    static func isGitOwnFailure(_ stderr: String) -> Bool {
        let markers = [
            "nothing to commit", "nothing added to commit", "no changes added to commit",
            "Please tell me who you are", "unable to auto-detect email address",
            "index.lock", "gpg failed to sign",
            "you have unmerged files", "Committing is not possible", "mark them as resolved",
            "could not apply", "CONFLICT (",
            "There is no merge in progress", "no cherry-pick or revert in progress", "No rebase in progress",
        ]
        return markers.contains { stderr.localizedCaseInsensitiveContains($0) }
    }
}
