import Foundation

/// One move of a ref recorded in its reflog (`git log -g`), with the commit
/// worth recovering from it. Moves that leave work behind (a reset, an
/// amend, the start of a rebase, a branch moved with `branch -f`) offer the
/// commit the ref was on *before* them; the rest offer where it went.
nonisolated struct ReflogEntry: Sendable, Equatable, Identifiable, Hashable {
    /// Position in the reflog: 0 is the latest move (`HEAD@{0}`).
    let index: Int
    /// The commit the ref moved to.
    let movedTo: Commit
    /// Where the ref was before this move: the next older entry's commit.
    /// `nil` for the oldest entry read.
    let movedFrom: Commit?
    /// When the ref moved (the reflog's time, not the commit's).
    let date: Date
    /// git's reflog subject, e.g. `reset: moving to HEAD~3`.
    let message: String
    let action: ReflogAction

    var id: Int { index }

    /// The entry points at where the ref was before the move.
    var showsPreviousState: Bool { action.leavesWorkBehind && movedFrom != nil }

    /// The commit this entry offers to recover.
    var commit: Commit { showsPreviousState ? movedFrom ?? movedTo : movedTo }

    /// What happened, in words: "Before reset to abc1234", "Rebase finished".
    var title: String {
        let to = movedTo.shortSha
        let before = showsPreviousState
        switch action {
        case .commit:
            return String(localized: "reflog.commit", defaultValue: "Commit")
        case .initialCommit:
            return String(localized: "reflog.initialCommit", defaultValue: "Initial commit")
        case .amend:
            return before
                ? String(localized: "reflog.beforeAmend", defaultValue: "Before amend")
                : String(localized: "reflog.amend", defaultValue: "Amended commit")
        case .mergeCommit:
            return String(localized: "reflog.mergeCommit", defaultValue: "Merge commit")
        case .cherryPick:
            return String(localized: "reflog.cherryPick", defaultValue: "Cherry-pick")
        case .revert:
            return String(localized: "reflog.revert", defaultValue: "Revert")
        case .reset:
            return before
                ? String(localized: "Before reset to \(to)")
                : String(localized: "Reset to \(to)")
        case .checkout(_, let target):
            let name = Self.display(target)
            return String(localized: "Checked out \(name)")
        case .merge(let branch, let fastForward):
            return fastForward
                ? String(localized: "Fast-forwarded to \(branch)")
                : String(localized: "Merged \(branch)")
        case .rebaseStart(let onto, let pull):
            guard before else { return String(localized: "reflog.rebaseStarted", defaultValue: "Rebase started") }
            if pull { return String(localized: "reflog.beforePullRebase", defaultValue: "Before pull with rebase") }
            let name = Self.display(onto)
            return String(localized: "Before rebase onto \(name)")
        case .rebaseStep(let phase, _):
            return String(localized: "Rebase step (\(phase))")
        case .rebaseFinish(let pull):
            return pull
                ? String(localized: "reflog.pullRebaseFinished", defaultValue: "Pull with rebase finished")
                : String(localized: "reflog.rebaseFinished", defaultValue: "Rebase finished")
        case .rebaseAbort:
            return String(localized: "reflog.rebaseAborted", defaultValue: "Rebase aborted")
        case .pull:
            return String(localized: "reflog.pull", defaultValue: "Pull")
        case .clone:
            return String(localized: "reflog.clone", defaultValue: "Cloned")
        case .branchCreated(let start):
            let name = Self.display(start)
            return String(localized: "Branch created from \(name)")
        case .branchReset(let target):
            let name = Self.display(target)
            return before
                ? String(localized: "Before branch moved to \(name)")
                : String(localized: "Branch moved to \(name)")
        case .branchRenamed(let from, _):
            return String(localized: "Renamed from \(from)")
        case .other:
            return message
        }
    }

    /// A free branch name for "Create branch here", e.g. `recovered-abc1234`.
    func suggestedBranchName(avoiding taken: Set<String> = []) -> String {
        let base = "recovered-\(commit.shortSha)"
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// A ref as written in a reflog message: a full SHA shortened, a local
    /// branch without `refs/heads/`, anything else (`HEAD~1`, `main`) as is.
    static func display(_ ref: String) -> String {
        if ref.count >= 40, ref.allSatisfy(\.isHexDigit) { return String(ref.prefix(7)) }
        if ref.hasPrefix("refs/heads/") { return String(ref.dropFirst("refs/heads/".count)) }
        return ref
    }
}

/// What a reflog entry did, read from git's reflog subject. The subjects
/// are git's own (not localized, stable for years): `<command>[ (<phase>)]:
/// <detail>`, e.g. `commit (amend): Fix typo`, `rebase (finish): returning
/// to refs/heads/feature`, `pull --rebase (start): checkout 1a2b3c…`.
nonisolated enum ReflogAction: Sendable, Equatable, Hashable {
    case commit
    case initialCommit
    case amend
    /// A merge committed by hand after its conflicts were resolved.
    case mergeCommit
    case cherryPick
    case revert
    /// `reset: moving to <target>` (`git stash` writes one too).
    case reset(target: String)
    case checkout(from: String, to: String)
    case merge(branch: String, fastForward: Bool)
    /// `pull` is true for `pull --rebase`.
    case rebaseStart(onto: String, pull: Bool)
    /// A replayed commit (`pick`, `reword`, `squash`, `fixup`, `edit`,
    /// `continue`, `fast-forward`…): the phase as git writes it.
    case rebaseStep(phase: String, pull: Bool)
    case rebaseFinish(pull: Bool)
    case rebaseAbort(pull: Bool)
    case pull
    case clone
    case branchCreated(from: String)
    /// `branch -f` / `branch: Reset to <target>`.
    case branchReset(to: String)
    case branchRenamed(from: String, to: String)
    /// Anything else (`am`, `update-ref -m`, a tool's own message).
    case other

    /// The move left commits behind that the entry should offer to recover:
    /// where the ref was before it, not where it went.
    var leavesWorkBehind: Bool {
        switch self {
        case .amend, .reset, .rebaseStart, .branchReset: true
        default: false
        }
    }

    static func parse(_ message: String) -> ReflogAction {
        let head: Substring
        let detail: Substring
        if let colon = message.range(of: ": ") {
            head = message[..<colon.lowerBound]
            detail = message[colon.upperBound...]
        } else if message.hasSuffix(":") {
            head = message.dropLast()
            detail = ""
        } else {
            head = Substring(message)
            detail = ""
        }

        let (command, phase) = split(head)
        switch command {
        case "commit":
            switch phase {
            case "initial": return .initialCommit
            case "amend": return .amend
            case "merge": return .mergeCommit
            case "cherry-pick": return .cherryPick
            default: return .commit
            }
        case "cherry-pick":
            return .cherryPick
        case "revert":
            return .revert
        case "reset":
            return .reset(target: String(detail.removingPrefix("moving to ")))
        case "checkout":
            // Ref names can't contain spaces, so " to " splits them exactly.
            let moving = detail.removingPrefix("moving from ")
            let parts = moving.components(separatedBy: " to ")
            guard parts.count == 2 else { return .other }
            return .checkout(from: parts[0], to: parts[1])
        case "clone":
            return .clone
        case "branch":
            if detail.hasPrefix("Created from ") {
                return .branchCreated(from: String(detail.removingPrefix("Created from ")))
            }
            if detail.hasPrefix("Reset to ") {
                return .branchReset(to: String(detail.removingPrefix("Reset to ")))
            }
            return .other
        case "Branch":
            let parts = detail.removingPrefix("renamed ").components(separatedBy: " to ")
            guard parts.count == 2 else { return .other }
            return .branchRenamed(from: ReflogEntry.display(parts[0]), to: ReflogEntry.display(parts[1]))
        default:
            break
        }

        // `merge <branch>: Fast-forward` / `merge <branch>: Merge made by…`
        if command.hasPrefix("merge "), phase == nil {
            let branch = String(command.dropFirst("merge ".count))
            return .merge(branch: branch, fastForward: detail.hasPrefix("Fast-forward"))
        }

        // `rebase`, `rebase -i`, `pull`, `pull --rebase`, `pull -q --rebase`…
        let word = command.split(separator: " ").first.map(String.init) ?? ""
        let isPull = word == "pull"
        if word == "rebase" || (isPull && phase != nil) {
            // git before 2.26: `rebase finished: returning to refs/heads/x`.
            if command == "rebase finished" { return .rebaseFinish(pull: false) }
            switch phase {
            case "start":
                return .rebaseStart(onto: String(detail.removingPrefix("checkout ")), pull: isPull)
            case "finish":
                return .rebaseFinish(pull: isPull)
            case "abort":
                return .rebaseAbort(pull: isPull)
            case let phase?:
                return .rebaseStep(phase: phase, pull: isPull)
            case nil:
                // `rebase: fast-forward` and the like.
                return .rebaseStep(phase: String(detail), pull: false)
            }
        }
        if isPull { return .pull }
        return .other
    }

    /// `rebase -i (finish)` → (`rebase -i`, `finish`); `commit` → (`commit`, nil).
    private static func split(_ head: Substring) -> (command: String, phase: String?) {
        guard head.hasSuffix(")"), let open = head.lastIndex(of: "(") else {
            return (String(head), nil)
        }
        let phase = head[head.index(after: open)..<head.index(before: head.endIndex)]
        let command = head[..<open].trimmingCharacters(in: .whitespaces)
        return (command, String(phase))
    }
}

nonisolated private extension Substring {
    func removingPrefix(_ prefix: String) -> Substring {
        hasPrefix(prefix) ? dropFirst(prefix.count) : self
    }
}
