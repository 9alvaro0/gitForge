import Foundation

/// Everything a branch or tag row and the inspector can do, wired once by
/// `BranchesView` so rows and inspector don't each take a dozen closures.
struct BranchActions {
    let checkout: (GitRef) -> Void
    /// `target == nil` merges into the current branch.
    let merge: (GitRef, GitRef?) -> Void
    let rebase: (GitRef) -> Void
    let rename: (GitRef) -> Void
    let delete: (GitRef) -> Void
    let pushTag: (GitRef) -> Void
    let deleteTag: (GitRef) -> Void

    static let none = BranchActions(
        checkout: { _ in }, merge: { _, _ in }, rebase: { _ in }, rename: { _ in },
        delete: { _ in }, pushTag: { _ in }, deleteTag: { _ in }
    )
}
