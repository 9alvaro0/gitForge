import SwiftUI

/// Detail view for a single stash. Tabs: Overview / Files. Drops the
/// Commits tab the PR detail has — a stash is a single commit (technically a
/// merge commit with index/untracked parents, but conceptually one snapshot).
struct StashDetailView: View {
    @Bindable var viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @State private var tab: Tab = .overview
    @State private var dropTarget: Stash?
    @State private var diffModeOverride: DiffPane.ViewMode?

    private var diffMode: Binding<DiffPane.ViewMode> {
        Binding(
            get: { diffModeOverride ?? theme.defaultDiffMode },
            set: { diffModeOverride = $0 }
        )
    }

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case overview, files
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: "Overview"
            case .files:    "Files"
            }
        }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            if let stash = viewModel.selectedStash {
                StashDetailHeader(
                    stash: stash,
                    onBack:  { viewModel.closeStashDetail() },
                    onApply: { Task { await runApply(stash, drop: false) } },
                    onPop:   { Task { await runApply(stash, drop: true)  } },
                    onDrop:  { dropTarget = stash }
                )
            }
            StashDetailTabBar(tab: $tab, loading: viewModel.stashDetailLoading)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .confirmationDialog("Drop \(dropTarget?.reference ?? "")?",
                            isPresented: dropAlertBinding,
                            titleVisibility: .visible) {
            Button("Drop", role: .destructive) {
                if let stash = dropTarget {
                    Task { await runDrop(stash) }
                }
                dropTarget = nil
            }
            Button("Cancel", role: .cancel) { dropTarget = nil }
        } message: {
            Text("Discards the stash. This can't be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let error = viewModel.stashDetailError, viewModel.stashDetail == nil {
                EmptyState(icon: .warn, title: "Couldn't load stash", subtitle: error) {
                    GFButton(title: "Retry", style: .primary) {
                        Task { await viewModel.loadStashDetail() }
                    }
                }
            } else {
                switch tab {
                case .overview:
                    StashOverviewTab(detail: viewModel.stashDetail)
                case .files:
                    StashFilesTab(viewModel: viewModel, diffMode: diffMode)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropAlertBinding: Binding<Bool> {
        Binding(get: { dropTarget != nil }, set: { if !$0 { dropTarget = nil } })
    }

    private func runApply(_ stash: Stash, drop: Bool) async {
        let outcome = await viewModel.applyStash(stash, drop: drop)
        switch outcome {
        case .clean:
            appState.ui.activeToast = ToastMessage(
                message: drop ? "Popped \(stash.reference)" : "Applied \(stash.reference)",
                kind: .ok)
            // Pop removed the stash; close the detail to bounce back to the list.
            if drop { viewModel.closeStashDetail() }
        case .conflicts:
            appState.ui.activeToast = ToastMessage(
                message: "Stash applied with conflicts — resolve to continue",
                kind: .warn)
            appState.ui.workspaceSection = .conflict
        case .failed(let message):
            appState.ui.activeToast = ToastMessage(message: message, kind: .error)
        }
    }

    private func runDrop(_ stash: Stash) async {
        switch await viewModel.dropStash(stash) {
        case .success:
            appState.ui.activeToast = ToastMessage(message: "Dropped \(stash.reference)", kind: .ok)
            viewModel.closeStashDetail()
        case .failure(let err):
            appState.ui.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error)
        }
    }
}

#Preview("Detail") {
    @Previewable @State var theme = AppTheme()
    StashDetailView(viewModel: .previewWithStashDetail)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}

#Preview("Loading") {
    @Previewable @State var theme = AppTheme()
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.previewWithStashes
        v.selectedStash = Stash.previewSamples.first
        v.stashDetailLoading = true
        return v
    }()
    StashDetailView(viewModel: vm)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
