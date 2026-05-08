import SwiftUI
import UniformTypeIdentifiers

/// Payload attached to a `BranchChip` when dragged from the History graph.
/// `sourceSha` lets the drop target detect a no-op (drop on the row the chip
/// already points at) and decline early, before any dialog is presented.
///
/// Wire format is a JSON string carried as `public.utf8-plain-text`. We tried
/// a custom UTI via `UTType(exportedAs:)` first — in-app drops would never
/// fire on macOS because the dynamic UTI didn't roundtrip through the drag
/// pasteboard. Using a built-in UTI sidesteps the registration problem; the
/// `dropDestination(for: DraggedBranch.self)` machinery still routes only to
/// our handlers because SwiftUI matches by `Transferable` type, not by raw
/// pasteboard tag.
struct DraggedBranch: Codable, Transferable, Equatable {
    let name: String
    /// `true` when the dragged chip is the currently checked-out branch — drop
    /// handlers route to `git reset` instead of `git branch -f`.
    let isCurrent: Bool
    /// `true` for `refs/heads/*`. Drag is gated to local branches only, so
    /// this is always `true` in practice; carried explicitly so a future
    /// "drag remote branch" feature stays honest.
    let isLocal: Bool
    let sourceSha: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { (branch: DraggedBranch) -> String in
            let data = try JSONEncoder().encode(branch)
            return String(data: data, encoding: .utf8) ?? "{}"
        } importing: { (json: String) -> DraggedBranch in
            try JSONDecoder().decode(DraggedBranch.self, from: Data(json.utf8))
        }
    }
}

/// What the drop target observed at release time. The chip-vs-row distinction
/// is driven by SwiftUI hit-testing — `.dropDestination` on a chip wins over
/// the same modifier on its enclosing row, so the host gets exactly one of
/// these two cases per drop.
enum BranchDropContext: Equatable {
    /// Drop landed on the empty area of a commit row. Action: move source.
    case onCommit(targetSha: String)
    /// Drop landed on another local-branch chip. Action: merge / rebase.
    case onBranch(targetBranchName: String, targetSha: String)
}
