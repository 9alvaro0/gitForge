import SwiftUI

/// Branches & Tags: one scope (Local / Remote / Tags) at a time in a table
/// grouped by folder (`feature/`, `release/`…), with the selected ref's
/// inspector on the right.
struct BranchesView: View {
    @Bindable var viewModel: RepositoryViewModel

    @State private var filter: String = ""
    @State private var scope: BranchScope = .local
    @State private var selectedID: String?
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

    private func refs(in scope: BranchScope) -> [GitRef] {
        switch scope {
        case .local: viewModel.localBranches
        case .remote: viewModel.remoteBranches
        case .tags: viewModel.tags
        }
    }

    private var scopedRefs: [GitRef] { refs(in: scope).filter(matchesFilter) }
    private var currentBranchName: String? { viewModel.currentBranchName }

    /// The selection when it belongs to this scope; otherwise, in Local, the
    /// current branch, so the inspector is never blank on first open.
    private var inspectedRef: GitRef? {
        let pool = refs(in: scope)
        if let selectedID, let ref = pool.first(where: { $0.id == selectedID }) { return ref }
        guard scope == .local else { return nil }
        return pool.first { $0.name == currentBranchName }
    }

    private func matchesFilter(_ ref: GitRef) -> Bool {
        filter.isEmpty || ref.name.localizedCaseInsensitiveContains(filter)
    }

    // MARK: Body

    var body: some View {
        @Bindable var ui = ui
        content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.bgContent)
        .navigationTitle("Branches & Tags")
        .searchable(text: $filter, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Scope", selection: $scope) {
                    ForEach(BranchScope.allCases) { scope in
                        Text("\(scope.title) \(refs(in: scope).count)").tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .help("Local branches, remote branches or tags")
            }
            if scope == .tags {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await runPushAllTags() } } label: {
                        Label("Push tags", systemImage: "arrow.up.to.line")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("Push all tags to origin")
                    .disabled(viewModel.tags.isEmpty)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { ui.newBranchSheetVisible = true } label: {
                    Label("New branch…", systemImage: "plus")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.glassProminent)
            }
        }
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

    /// Spec §4.6: the inspector is 480 wide, 360 below a 1280 window.
    private static let wideWindow: CGFloat = 1280
    private static let sidebarAllowance: CGFloat = 240

    private var content: some View {
        GeometryReader { geo in
            let inspectorWidth: CGFloat = geo.size.width + Self.sidebarAllowance >= Self.wideWindow ? 480 : 360
            HStack(spacing: 0) {
                table
                Rectangle().fill(theme.colors.separator).frame(width: 1)
                inspector
                    .frame(width: inspectorWidth)
                    .background(theme.colors.bgElevated)
            }
        }
    }

    @ViewBuilder
    private var table: some View {
        if hasActiveFilter && scopedRefs.isEmpty {
            EmptyState(icon: .search, title: "Nothing matches “\(filter)”") {
                GFButton(title: "Clear filter", size: .small) { filter = "" }
            }
        } else {
            BranchTable(
                scope: scope,
                refs: scopedRefs,
                currentBranchName: currentBranchName,
                availableTargets: viewModel.localBranches,
                selectedID: $selectedID,
                actions: actions
            )
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let ref = inspectedRef {
            BranchInspector(ref: ref, currentBranchName: currentBranchName, actions: actions)
        } else {
            EmptyState(icon: scope == .tags ? .tag : .branch,
                       title: scope == .tags ? "Select a tag" : "Select a branch",
                       subtitle: "Its upstream, last commit and actions show here.")
        }
    }

    private var hasActiveFilter: Bool {
        !filter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var actions: BranchActions {
        BranchActions(
            checkout: handleCheckout,
            merge: { source, target in mergeRequest = MergeRequest(source: source, target: target) },
            rebase: { rebaseTarget = $0 },
            rename: { renameTarget = $0; renameDraft = $0.name },
            delete: { deleteTarget = $0 },
            pushTag: { ref in Task { await runPushTag(ref) } },
            deleteTag: { deleteTargetTag = $0 }
        )
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
