import Foundation

/// Whether the host lets the PR/MR merge right now, as it says (GitHub's
/// `mergeable_state`, GitLab's `detailed_merge_status`), in words.
nonisolated struct HostMergeStatus: Equatable, Sendable {
    enum Verdict: Equatable, Sendable { case ready, waiting, blocked }

    let verdict: Verdict
    /// Why, in the host's terms, already localized.
    var reasons: [String] = []
    /// GitHub's `blocked` doesn't say which rule: the reasons gitForge can
    /// work out (failing checks, reviews) go first.
    var includesLocalReasons = false
    /// GitHub's `unstable`: failing checks that aren't required.
    var failingChecksOptional = false
    /// GitHub works mergeability out in the background: ask again shortly.
    var stillComputing = false

    static var checking: String { String(localized: "checking mergeability…") }
    static var conflicts: String { String(localized: "conflicts with the target branch") }
    static var draft: String { String(localized: "still a draft") }
}

/// How GitHub merges a PR, as its API names them.
nonisolated enum MergeMethod: String, Sendable, CaseIterable {
    case squash, merge, rebase
}

/// A GitLab project's merge method: fixed per project, not chosen per MR.
nonisolated enum GitLabMergeMethod: String, Sendable {
    case merge, rebaseMerge = "rebase_merge", fastForward = "ff"
}

/// A GitLab project's squash policy.
nonisolated enum GitLabSquashOption: String, Sendable {
    case never, always, defaultOn = "default_on", defaultOff = "default_off"
}

/// An editable commit message in the merge sheet: GitHub's title and body,
/// GitLab's squash and merge commit messages (one multi-line text each).
nonisolated enum MergeMessageField: Hashable, Sendable {
    case title, body, squashMessage, mergeMessage
}

/// What the host lets this PR/MR merge with, read when the sheet opens.
nonisolated struct MergeOptions: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The methods the repo allows, in the order squash, merge, rebase.
        case github(methods: [MergeMethod])
        case gitlab(method: GitLabMergeMethod, squash: GitLabSquashOption)
    }

    let kind: Kind
    /// The source branch lives in the target repo (not a fork).
    let canDeleteSourceBranch: Bool
    /// GitHub: what the host will write in each message, where that's
    /// exactly known. GitLab resolves its templates on the server: empty.
    var defaultsByMethod: [MergeMethod: [MergeMessageField: String]] = [:]
    var initialMethod: MergeMethod?
    var initialSquash: Bool

    func defaults(for method: MergeMethod?) -> [MergeMessageField: String] {
        method.flatMap { defaultsByMethod[$0] } ?? [:]
    }

    /// GitLab offers "Squash commits" unless the project never squashes.
    var showsSquashToggle: Bool {
        guard case .gitlab(_, let squash) = kind else { return false }
        return squash != .never
    }

    /// GitLab projects that always squash: ticked and fixed.
    var squashLocked: Bool {
        guard case .gitlab(_, let squash) = kind else { return false }
        return squash == .always
    }

    /// The squash that will happen: GitHub's squash method, or GitLab's
    /// toggle as the project's policy allows it.
    func resolvedSquash(_ squash: Bool, method: MergeMethod?) -> Bool {
        switch kind {
        case .github: method == .squash
        case .gitlab(_, .always): true
        case .gitlab(_, .never): false
        case .gitlab: squash
        }
    }

    /// The messages the sheet shows (and may send) for a method and squash.
    func messageFields(method: MergeMethod?, squash: Bool) -> [MergeMessageField] {
        switch kind {
        case .github:
            switch method {
            case .squash, .merge: return [.title, .body]
            case .rebase, nil: return []
            }
        case .gitlab(let projectMethod, _):
            switch (projectMethod, squash) {
            case (.merge, false), (.rebaseMerge, false): return [.mergeMessage]
            case (.merge, true), (.rebaseMerge, true): return [.squashMessage, .mergeMessage]
            case (.fastForward, true): return [.squashMessage]
            case (.fastForward, false): return []
            }
        }
    }

    /// The confirm button says what will happen.
    func confirmTitle(method: MergeMethod?, squash: Bool) -> String {
        switch kind {
        case .github:
            switch method {
            case .squash: String(localized: "Squash and merge")
            case .merge: String(localized: "Create merge commit")
            case .rebase: String(localized: "Rebase and merge")
            case nil: String(localized: "Merge")
            }
        case .gitlab:
            squash ? String(localized: "Squash and merge") : String(localized: "Merge")
        }
    }
}

/// What the user set in the merge sheet. Messages they didn't touch show
/// the host's default and don't travel, so the host's own templates apply.
nonisolated struct MergeDraft: Equatable, Sendable {
    var method: MergeMethod?
    var squash: Bool
    var deleteSourceBranch: Bool
    private(set) var edits: [MergeMessageField: String] = [:]

    init(options: MergeOptions) {
        method = options.initialMethod
        squash = options.initialSquash
        deleteSourceBranch = options.canDeleteSourceBranch
    }

    mutating func setText(_ text: String, for field: MergeMessageField) {
        edits[field] = text
    }

    func text(for field: MergeMessageField, options: MergeOptions) -> String {
        edits[field] ?? options.defaults(for: method)[field] ?? ""
    }

    /// The request: only the edited messages the method shows, and never a
    /// branch deletion the host can't do (a fork).
    func input(options: MergeOptions, headSha: String?) -> MergeInput {
        let squash = options.resolvedSquash(squash, method: method)
        let shown = Set(options.messageFields(method: method, squash: squash))
        return MergeInput(method: method, squash: squash,
                          deleteSourceBranch: deleteSourceBranch && options.canDeleteSourceBranch,
                          messages: edits.filter { shown.contains($0.key) }, headSha: headSha)
    }
}

/// One merge request to the host.
nonisolated struct MergeInput: Equatable, Sendable {
    var method: MergeMethod?
    var squash: Bool
    var deleteSourceBranch: Bool
    var messages: [MergeMessageField: String]
    /// The head the user saw: the host refuses the merge if it moved.
    var headSha: String?
}

nonisolated struct MergeOutcome: Equatable, Sendable {
    /// The source branch is gone (or the host took it on to delete it).
    let branchDeleted: Bool
}
