import SwiftUI

/// Each dialog is driven by an optional binding on the parent state —
/// clearing the binding dismisses it.
struct BranchDialogs: ViewModifier {
    @Binding var deleteTarget: GitRef?
    @Binding var deleteForce: Bool
    @Binding var mergeRequest: BranchesView.MergeRequest?
    @Binding var rebaseTarget: GitRef?
    @Binding var deleteTargetTag: GitRef?
    let currentBranchName: String?
    let confirmDelete: (GitRef) -> Void
    let confirmMerge: (BranchesView.MergeRequest) -> Void
    let confirmRebase: (GitRef) -> Void
    let confirmDeleteTag: (GitRef, _ alsoOnRemote: Bool) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Delete \(deleteTarget?.name ?? "")?",
                                isPresented: presence($deleteTarget),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let ref = deleteTarget { confirmDelete(ref) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This removes the local branch reference. Use force-delete if it has unmerged commits.")
            }
            .confirmationDialog(mergeTitle,
                                isPresented: presence($mergeRequest),
                                titleVisibility: .visible) {
                Button("Merge") {
                    if let req = mergeRequest { confirmMerge(req) }
                    mergeRequest = nil
                }
                Button("Cancel", role: .cancel) { mergeRequest = nil }
            } message: {
                Text(mergeMessage)
            }
            .confirmationDialog("Rebase \(currentBranchName ?? "current") onto \(rebaseTarget?.displayName ?? "")?",
                                isPresented: presence($rebaseTarget),
                                titleVisibility: .visible) {
                Button("Rebase") {
                    if let ref = rebaseTarget { confirmRebase(ref) }
                    rebaseTarget = nil
                }
                Button("Cancel", role: .cancel) { rebaseTarget = nil }
            } message: {
                Text("Replays \(currentBranchName ?? "current") on top of \(rebaseTarget?.displayName ?? ""). You'll need a force push afterwards.")
            }
            .confirmationDialog("Delete tag \(deleteTargetTag?.name ?? "")?",
                                isPresented: presence($deleteTargetTag),
                                titleVisibility: .visible) {
                Button("Delete locally", role: .destructive) {
                    if let ref = deleteTargetTag { confirmDeleteTag(ref, false) }
                    deleteTargetTag = nil
                }
                Button("Delete locally + remote", role: .destructive) {
                    if let ref = deleteTargetTag { confirmDeleteTag(ref, true) }
                    deleteTargetTag = nil
                }
                Button("Cancel", role: .cancel) { deleteTargetTag = nil }
            } message: {
                Text("Local-only is reversible (re-tag the same sha). Removing from origin notifies anyone who already pulled it.")
            }
    }

    private var mergeTitle: String {
        guard let req = mergeRequest else { return "" }
        let target = req.target?.displayName ?? currentBranchName ?? "current"
        return "Merge \(req.source.displayName) into \(target)?"
    }

    private var mergeMessage: String {
        guard let req = mergeRequest else { return "" }
        let target = req.target?.displayName ?? currentBranchName ?? "current"
        if let t = req.target, t.name != currentBranchName {
            return "Will check out \(target) first, then merge \(req.source.displayName) into it. Conflicts route you to the Conflicts view."
        }
        return "Brings \(req.source.displayName) into \(target). Conflicts route you to the Conflicts view."
    }

    /// `confirmationDialog(isPresented:)` insists on a `Bool` binding even
    /// when the trigger state is an optional — bridge with a presence check.
    private func presence<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil },
                set: { if !$0 { binding.wrappedValue = nil } })
    }
}
