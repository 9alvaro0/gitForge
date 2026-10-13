import SwiftUI

/// What dropping the dragged branch on the target under the cursor would do,
/// for the HUD. SwiftUI only reveals the dragged payload on drop, so the
/// intent describes the target; the dialog after the drop names both sides.
nonisolated enum BranchDropIntent: Equatable, Sendable {
    /// Over a commit row: the branch moves there (reset when checked out).
    case commit(shortSha: String, subject: String)
    /// Over another local branch's chip: merge or rebase, chosen after drop.
    case branch(name: String)

    var title: String {
        switch self {
        case .commit(let sha, _): "Move the branch to \(sha)"
        case .branch(let name): "Merge or rebase onto \(name)"
        }
    }

    var detail: String {
        switch self {
        case .commit(_, let subject):
            subject
        case .branch:
            "Drop, then pick merge or rebase"
        }
    }

    var systemImage: String {
        switch self {
        case .commit: "arrow.right.to.line"
        case .branch: "arrow.triangle.merge"
        }
    }
}

/// The drop target currently under a dragged branch in History. One per
/// History view, handed to the rows' drop modifiers through the environment.
@MainActor @Observable
final class BranchDropTracker {
    private(set) var intent: BranchDropIntent?
    /// The hovered target's commit, for the HUD's graph preview.
    private(set) var targetSha: String?
    /// The branch being dragged. SwiftUI hands the payload only to the
    /// drop, so the drag sources record it when the drag starts.
    private(set) var source: (name: String, sha: String)?

    /// Called from the draggable payload's closure, which SwiftUI runs when
    /// the drag begins.
    func beginDrag(name: String, sha: String) {
        source = (name, sha)
    }

    /// Entering a target sets the intent; leaving clears it only if no other
    /// target took over in between (enter/leave events can arrive in either
    /// order when the cursor crosses from one row to the next).
    func hover(_ target: BranchDropIntent, targetSha: String? = nil, isOver: Bool) {
        if isOver {
            intent = target
            self.targetSha = targetSha
        } else if intent == target {
            intent = nil
            self.targetSha = nil
        }
    }

    /// The graph preview for the current hover, on the loaded commits.
    func preview(in commits: [Commit]) -> BranchDropPreview? {
        guard let intent, let source, let targetSha, source.sha != targetSha else { return nil }
        switch intent {
        case .branch: return .integrate(source: source.sha, target: targetSha, in: commits)
        case .commit: return .move(from: source.sha, to: targetSha, in: commits)
        }
    }

    func clear() {
        intent = nil
        targetSha = nil
        source = nil
    }
}

extension EnvironmentValues {
    @Entry var branchDropTracker: BranchDropTracker? = nil
}
