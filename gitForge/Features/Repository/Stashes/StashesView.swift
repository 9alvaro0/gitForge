import SwiftUI

/// List of `git stash` entries with apply / pop / drop per row, drill-in to
/// detail (overview + files), and a "Stash changes…" button when the working
/// tree is dirty.
struct StashesView: View {
    @Bindable var viewModel: RepositoryViewModel

    @State private var stashSheet = false
    @State private var stashMessage: String = ""
    @State private var dropTarget: Stash?
    @State private var diffModeOverride: DiffPane.ViewMode?

    @Environment(\.appPreferences) private var preferences

    private var diffMode: Binding<DiffPane.ViewMode> {
        Binding(
            get: { diffModeOverride ?? preferences.defaultDiffMode },
            set: { diffModeOverride = $0 }
        )
    }

    static let listWidth: CGFloat = 300

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    private var hasDirtyChanges: Bool { !viewModel.status.isClean }

    var body: some View {
        Group {
            if viewModel.stashes.isEmpty {
                EmptyState(
                    icon: .stash,
                    title: "No stashes",
                    subtitle: hasDirtyChanges
                        ? "Use \u{201C}Stash changes…\u{201D} to park your work in progress."
                        : "When you stash work in progress it'll show up here."
                )
            } else {
                HStack(spacing: 0) {
                    StashList(
                        stashes: viewModel.stashes,
                        selectedIndex: viewModel.stashDetail.selected?.index,
                        onSelect: { viewModel.stashDetail.select($0) },
                        onApply:  { stash in Task { await runApply(stash, drop: false) } },
                        onPop:    { stash in Task { await runApply(stash, drop: true)  } },
                        onDrop:   { stash in dropTarget = stash }
                    )
                    .frame(width: Self.listWidth)
                    Rectangle().fill(theme.colors.separator).frame(width: 1)
                    inspector
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.colors.bgElevated)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.bgContent)
        .navigationTitle("Stashes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    stashMessage = ""
                    stashSheet = true
                } label: {
                    Label("Stash changes…", systemImage: "tray.and.arrow.down")
                }
                // Icon only: with a title it falls into the toolbar's `»`
                // overflow at the minimum window width.
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
                .help("Stash changes…")
                .disabled(!hasDirtyChanges)
            }
        }
        // Open the newest stash so the inspector isn't blank on arrival, and
        // move on when the selected one is popped or dropped.
        .task(id: viewModel.stashes.map(\.sha)) {
            let selected = viewModel.stashDetail.selected
            if selected == nil || !viewModel.stashes.contains(where: { $0.sha == selected?.sha }) {
                if let first = viewModel.stashes.first {
                    viewModel.stashDetail.select(first)
                } else {
                    viewModel.stashDetail.close()
                }
            }
        }
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

    @ViewBuilder
    private var inspector: some View {
        if let stash = viewModel.stashDetail.selected {
            StashInspector(
                stash: stash,
                store: viewModel.stashDetail,
                diffMode: diffMode,
                onApply: { Task { await runApply(stash, drop: false) } },
                onPop: { Task { await runApply(stash, drop: true) } },
                onDrop: { dropTarget = stash }
            )
        } else {
            EmptyState(icon: .stash, title: "Select a stash")
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
