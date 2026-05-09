import SwiftUI

/// List of `git stash` entries with apply / pop / drop per row, drill-in to
/// detail (overview + files), and a "Stash changes…" button when the working
/// tree is dirty.
struct StashesView: View {
    @Bindable var viewModel: RepositoryViewModel

    @State private var stashSheet = false
    @State private var stashMessage: String = ""
    @State private var dropTarget: Stash?

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    private var hasDirtyChanges: Bool { !viewModel.status.isClean }

    var body: some View {
        Group {
            if viewModel.selectedStash != nil {
                StashDetailView(viewModel: viewModel)
            } else {
                listLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .sheet(isPresented: $stashSheet) {
            StashCreateSheet(
                message: $stashMessage,
                onCancel: { stashSheet = false },
                onStash: { Task { await runStash() } }
            )
        }
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

    private var listLayout: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ContentHeader(title: "Stashes") {
                MonoText("\(viewModel.stashes.count) stashed", dim: true)
            } right: {
                ToolButton(.stash, label: "Stash changes…", primary: true,
                           disabled: !hasDirtyChanges) {
                    stashMessage = ""
                    stashSheet = true
                }
            }
            StashList(
                stashes: viewModel.stashes,
                hasDirtyChanges: hasDirtyChanges,
                onSelect: { viewModel.selectStash($0) },
                onApply:  { stash in Task { await runApply(stash, drop: false) } },
                onPop:    { stash in Task { await runApply(stash, drop: true)  } },
                onDrop:   { stash in dropTarget = stash }
            )
        }
    }

    private func runApply(_ stash: Stash, drop: Bool) async {
        let outcome = await viewModel.applyStash(stash, drop: drop)
        switch outcome {
        case .clean:
            appState.ui.activeToast = ToastMessage(
                message: drop ? "Popped \(stash.reference)" : "Applied \(stash.reference)",
                kind: .ok)
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
        case .failure(let err):
            appState.ui.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error)
        }
    }

    private func runStash() async {
        let message = stashMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await viewModel.stashAll(message: message.isEmpty ? nil : message)
        if case .failure(let err) = result {
            appState.ui.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error
            )
        } else {
            appState.ui.activeToast = ToastMessage(message: "Stashed", kind: .ok)
        }
        stashSheet = false
    }

    private var dropAlertBinding: Binding<Bool> {
        Binding(get: { dropTarget != nil }, set: { if !$0 { dropTarget = nil } })
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    StashesView(viewModel: .previewWithStashes)
        .previewAppState(.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}

#Preview("Empty") {
    @Previewable @State var theme = AppTheme()
    StashesView(viewModel: .preview)
        .previewAppState(.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}

#Preview("Detail") {
    @Previewable @State var theme = AppTheme()
    StashesView(viewModel: .previewWithStashDetail)
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
