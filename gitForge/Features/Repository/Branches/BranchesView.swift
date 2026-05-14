import SwiftUI

/// Local + remote + tags grouped by folder (`feature/`, `release/`, …) so
/// big repos don't drown the list.
struct BranchesView: View {
    @Bindable var viewModel: RepositoryViewModel

    @State private var filter: String = ""
    /// Driven by `WorkspaceUI.newBranchSheetVisible` so the File ▸ New Branch (⌘B)
    /// menu and the local "+" button share one presentation path.
    @State private var newBranchName: String = ""
    @State private var renameTarget: GitRef?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: GitRef?
    @State private var mergeRequest: MergeRequest?
    @State private var rebaseTarget: GitRef?
    @State private var deleteTargetTag: GitRef?

    @Environment(AppState.self) private var appState
    @Environment(WorkspaceUI.self) private var ui
    @Environment(\.appTheme) private var theme

    /// `target == nil` means the current branch.
    struct MergeRequest: Identifiable, Equatable {
        let id = UUID()
        let source: GitRef
        let target: GitRef?
    }

    // MARK: Filtered slices

    private var localBranches: [GitRef]  { viewModel.localBranches.filter(matchesFilter) }
    private var remoteBranches: [GitRef] { viewModel.remoteBranches.filter(matchesFilter) }
    private var tags: [GitRef]           { viewModel.tags.filter(matchesFilter) }
    private var currentBranchName: String? { viewModel.currentBranchName }

    private func matchesFilter(_ ref: GitRef) -> Bool {
        filter.isEmpty || ref.name.localizedCaseInsensitiveContains(filter)
    }

    /// Maintained by the ViewModel as a side-effect of every log mutation;
    /// reading it here is a single property fetch rather than the previous
    /// per-body Dictionary rebuild over `viewModel.commits`.
    private var commitDateBySha: [String: Date] {
        viewModel.commitDateBySha
    }

    // MARK: Body

    var body: some View {
        @Bindable var ui = ui
        VStack(spacing: DesignTokens.Spacing.none) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .sheet(isPresented: $ui.newBranchSheetVisible) {
            BranchInputSheet(
                title: "New branch",
                placeholder: "feat/awesome",
                confirmTitle: "Create & checkout",
                text: $newBranchName,
                confirmDisabled: newBranchName.isEmpty,
                onCancel: { ui.newBranchSheetVisible = false },
                onConfirm: { name in
                    Task {
                        _ = await viewModel.createBranch(name: name, checkout: true)
                        ui.newBranchSheetVisible = false
                    }
                }
            )
        }
        // Either entry point — local "+" or the ⌘B menu — opens with a clean input.
        .onChange(of: ui.newBranchSheetVisible) { _, isVisible in
            if isVisible { newBranchName = "" }
        }
        .sheet(item: $renameTarget) { ref in
            BranchInputSheet(
                title: "Rename \(ref.name)",
                placeholder: ref.name,
                confirmTitle: "Rename",
                text: $renameDraft,
                confirmDisabled: renameDraft.isEmpty || renameDraft == ref.name,
                onCancel: { renameTarget = nil },
                onConfirm: { newName in
                    Task {
                        _ = await viewModel.renameBranch(from: ref.name, to: newName)
                        renameTarget = nil
                    }
                }
            )
        }
        .modifier(BranchDialogs(
            deleteTarget: $deleteTarget,
            mergeRequest: $mergeRequest,
            rebaseTarget: $rebaseTarget,
            deleteTargetTag: $deleteTargetTag,
            currentBranchName: currentBranchName,
            confirmDelete: { ref, force in Task { _ = await viewModel.deleteBranch(ref, force: force) } },
            confirmMerge: { req in Task { await runMerge(request: req) } },
            confirmRebase: { ref in Task { await runRebase(ref: ref) } },
            confirmDeleteTag: { ref, alsoRemote in Task { await runDeleteTag(ref, alsoOnRemote: alsoRemote) } }
        ))
    }

    // MARK: Layout

    private var header: some View {
        ContentHeader(title: "Branches") {
            EmptyView()
        } right: {
            GFTextField(placeholder: "Filter branches…", text: $filter).frame(width: 220)
            ToolButton(.push, label: "Push tags", disabled: viewModel.tags.isEmpty) {
                Task { await runPushAllTags() }
            }
            ToolButton(.plus, label: "New branch", primary: true) {
                ui.newBranchSheetVisible = true
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xhuge) {
                if hasActiveFilter && filteredEverything.isEmpty {
                    filterEmptyState
                } else {
                    BranchListSection(
                        title: "Local",
                        refs: localBranches,
                        availableTargets: viewModel.localBranches,
                        currentBranchName: currentBranchName,
                        commitDateBySha: commitDateBySha,
                        onCheckout: handleCheckout,
                        onRename: { renameTarget = $0; renameDraft = $0.name },
                        onDelete: { deleteTarget = $0 },
                        onMerge: { source, target in mergeRequest = MergeRequest(source: source, target: target) },
                        onRebase: { rebaseTarget = $0 }
                    )
                    BranchListSection(
                        title: "Remote",
                        refs: remoteBranches,
                        availableTargets: viewModel.localBranches,
                        currentBranchName: nil,
                        commitDateBySha: commitDateBySha,
                        onCheckout: handleCheckout,
                        onRename: nil,
                        onDelete: nil,
                        onMerge: { source, target in mergeRequest = MergeRequest(source: source, target: target) },
                        onRebase: { rebaseTarget = $0 }
                    )
                    if !tags.isEmpty {
                        BranchTagsSection(
                            tags: tags,
                            onPush:   { ref in Task { await runPushTag(ref) } },
                            onDelete: { ref in deleteTargetTag = ref }
                        )
                    }
                }
            }
            .padding(DesignTokens.Spacing.xxxxl)
        }
    }

    private var hasActiveFilter: Bool {
        !filter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Total count across all sections after filtering. Lets the empty-state
    /// fire when the filter matches nothing instead of rendering three
    /// "No branches." stubs side by side.
    private var filteredEverything: [GitRef] {
        localBranches + remoteBranches + tags
    }

    private var filterEmptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Text("No branches or tags match “\(filter)”.")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg2)
            GFButton(title: "Clear filter", size: .small) { filter = "" }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, DesignTokens.Spacing.xxxxl)
    }

    // MARK: Handlers

    private func handleCheckout(_ ref: GitRef) {
        Task { _ = await viewModel.checkoutBranch(ref) }
    }

    private func runMerge(request: MergeRequest) async {
        let outcome = await viewModel.mergeBranch(source: request.source, into: request.target)
        let targetLabel = request.target?.displayName ?? currentBranchName ?? "HEAD"
        report(outcome,
               success: "Merged \(request.source.displayName) into \(targetLabel)",
               conflicts: "Merge has conflicts — resolve to continue")
    }

    private func runRebase(ref: GitRef) async {
        let outcome = await viewModel.rebaseOnto(ref)
        report(outcome,
               success: "Rebased \(currentBranchName ?? "HEAD") onto \(ref.displayName)",
               conflicts: "Rebase has conflicts — resolve to continue")
    }

    private func report(_ outcome: RepositoryViewModel.IntegrationOutcome,
                        success: String,
                        conflicts: String) {
        switch outcome {
        case .clean:
            toast(success, kind: .ok)
        case .conflicts:
            appState.ui.workspaceSection = .conflict
            toast(conflicts, kind: .warn)
        case .failed(let message):
            toast(message, kind: .error)
        }
    }

    // MARK: Tag handlers

    private func runPushTag(_ ref: GitRef) async {
        toast(await viewModel.pushTag(ref), success: "Pushed \(ref.name)")
    }

    private func runPushAllTags() async {
        toast(await viewModel.pushAllTags(), success: "Pushed all tags")
    }

    private func runDeleteTag(_ ref: GitRef, alsoOnRemote: Bool) async {
        if alsoOnRemote {
            if case .failure(let err) = await viewModel.pushDeleteTag(ref) {
                toast(err.toastMessage, kind: .error)
                return
            }
        }
        let suffix = alsoOnRemote ? " (local + remote)" : " (local)"
        toast(await viewModel.deleteTag(ref), success: "Deleted \(ref.name)\(suffix)")
    }

    // MARK: Toast helpers

    private func toast(_ message: String, kind: ToastMessage.Kind) {
        appState.ui.activeToast = ToastMessage(message: message, kind: kind)
    }

    private func toast(_ result: Result<Void, Error>, success: String) {
        switch result {
        case .success:           toast(success, kind: .ok)
        case .failure(let err):  toast(err.toastMessage, kind: .error)
        }
    }
}

private extension Error {
    var toastMessage: String {
        (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    BranchesView(viewModel: RepositoryViewModel.preview)
        .previewAppState(.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
