import SwiftUI

/// "Move local branch X to commit Y" — fired when a non-current branch chip
/// is dropped on another commit row.
struct MoveBranchRequest: Identifiable, Equatable {
    let id = UUID()
    let branch: GitRef
    let targetSha: String
    let targetShortSha: String
}

/// "Reset HEAD to commit Y" — fired when the current branch chip is dropped
/// on another commit row. The dialog asks for a reset mode (soft/mixed/hard).
struct ResetHeadRequest: Identifiable, Equatable {
    let id = UUID()
    let branchName: String
    let targetSha: String
    let targetShortSha: String
}

/// "Merge X into Y or rebase Y onto X" — fired when a chip is dropped on
/// another local-branch chip. The dialog offers both options plus cancel.
struct MergeRebaseRequest: Identifiable, Equatable {
    let id = UUID()
    let source: GitRef
    let target: GitRef
}

/// Hosts the three confirmation dialogs that arm when a `BranchChip` is
/// dropped on a commit row or another chip. Extracted from the main view
/// because chaining three more `confirmationDialog` modifiers on top of
/// `HistoryView`'s body was tipping the type-checker into timeouts on debug
/// builds (see feedback note `swiftui_typecheck`).
struct BranchDropDialogs: ViewModifier {
    @Binding var moveRequest: MoveBranchRequest?
    @Binding var resetRequest: ResetHeadRequest?
    @Binding var mergeRebaseRequest: MergeRebaseRequest?
    let onMove: (MoveBranchRequest) -> Void
    let onReset: (ResetHeadRequest, GitCLI.ResetMode) -> Void
    let onMerge: (MergeRebaseRequest) -> Void
    let onRebase: (MergeRebaseRequest) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                moveTitle,
                isPresented: moveBinding,
                titleVisibility: .visible
            ) {
                Button("Move") {
                    if let r = moveRequest { onMove(r) }
                    moveRequest = nil
                }
                Button("Cancel", role: .cancel) { moveRequest = nil }
            } message: {
                Text("Force-updates the local branch (`git branch -f`). Existing commits aren't lost — they'll just no longer be reachable from this branch.")
            }
            .confirmationDialog(
                resetTitle,
                isPresented: resetBinding,
                titleVisibility: .visible
            ) {
                Button("Soft (keep changes staged)") {
                    if let r = resetRequest { onReset(r, .soft) }
                    resetRequest = nil
                }
                Button("Mixed (keep changes unstaged)") {
                    if let r = resetRequest { onReset(r, .mixed) }
                    resetRequest = nil
                }
                Button("Hard (discard everything)", role: .destructive) {
                    if let r = resetRequest { onReset(r, .hard) }
                    resetRequest = nil
                }
                Button("Cancel", role: .cancel) { resetRequest = nil }
            } message: {
                Text("""
                Moves \(resetRequest?.branchName ?? "HEAD") and HEAD to \(resetRequest?.targetShortSha ?? "the target").

                • Soft: commits after the target stay as staged changes.
                • Mixed: commits after the target stay as unstaged changes.
                • Hard: every commit and uncommitted change after the target is DISCARDED. Recoverable only via `git reflog` for a limited time.
                """)
            }
            .confirmationDialog(
                mergeRebaseTitle,
                isPresented: mergeRebaseBinding,
                titleVisibility: .visible
            ) {
                Button("Merge \(mergeRebaseRequest?.source.displayName ?? "") into \(mergeRebaseRequest?.target.displayName ?? "")") {
                    if let r = mergeRebaseRequest { onMerge(r) }
                    mergeRebaseRequest = nil
                }
                Button("Rebase \(mergeRebaseRequest?.source.displayName ?? "") onto \(mergeRebaseRequest?.target.displayName ?? "")") {
                    if let r = mergeRebaseRequest { onRebase(r) }
                    mergeRebaseRequest = nil
                }
                Button("Cancel", role: .cancel) { mergeRebaseRequest = nil }
            } message: {
                Text(Self.mergeRebaseMessage(for: mergeRebaseRequest))
            }
    }

    private var moveBinding: Binding<Bool> {
        Binding(get: { moveRequest != nil }, set: { if !$0 { moveRequest = nil } })
    }
    private var resetBinding: Binding<Bool> {
        Binding(get: { resetRequest != nil }, set: { if !$0 { resetRequest = nil } })
    }
    private var mergeRebaseBinding: Binding<Bool> {
        Binding(get: { mergeRebaseRequest != nil }, set: { if !$0 { mergeRebaseRequest = nil } })
    }

    private var moveTitle: String {
        guard let r = moveRequest else { return "" }
        return "Move \(r.branch.displayName) to \(r.targetShortSha)?"
    }

    private var resetTitle: String {
        guard let r = resetRequest else { return "" }
        return "Reset \(r.branchName) to \(r.targetShortSha)?"
    }

    private var mergeRebaseTitle: String {
        guard let r = mergeRebaseRequest else { return "" }
        return "\(r.source.displayName) → \(r.target.displayName)"
    }

    /// Spell out both paths so the user knows what each button does. Rebase
    /// rewrites commits — flag it explicitly so the difference vs Merge is
    /// visible before the button is pressed.
    static func mergeRebaseMessage(for request: MergeRebaseRequest?) -> String {
        guard let r = request else { return "" }
        return """
        Merge: replays \(r.source.displayName) into \(r.target.displayName) as a new merge commit. History is preserved.

        Rebase: rewrites every commit on \(r.source.displayName) on top of \(r.target.displayName). If \(r.source.displayName) is already pushed, you'll need a force push afterwards.

        Either action may switch branches first if the destination isn't checked out.
        """
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var moveReq: MoveBranchRequest? = nil
    @Previewable @State var resetReq: ResetHeadRequest? = nil
    @Previewable @State var mergeReq: MergeRebaseRequest? = nil

    VStack(spacing: 12) {
        Button("Trigger move dialog") {
            moveReq = MoveBranchRequest(branch: GitRef.previewSamples[0], targetSha: "abc1234abcdef", targetShortSha: "abc1234")
        }
        Button("Trigger reset dialog") {
            resetReq = ResetHeadRequest(branchName: "main", targetSha: "abc1234abcdef", targetShortSha: "abc1234")
        }
        Button("Trigger merge/rebase dialog") {
            mergeReq = MergeRebaseRequest(source: GitRef.previewSamples[0], target: GitRef.previewSamples[1])
        }
    }
    .padding(24)
    .frame(width: 360, height: 220)
    .background(theme.palette.bg2)
    .modifier(BranchDropDialogs(
        moveRequest: $moveReq,
        resetRequest: $resetReq,
        mergeRebaseRequest: $mergeReq,
        onMove: { _ in }, onReset: { _, _ in }, onMerge: { _ in }, onRebase: { _ in }
    ))
    .appTheme(theme)
}
