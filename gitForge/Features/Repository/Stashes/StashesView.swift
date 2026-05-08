import SwiftUI

/// `.gf-view-stashes` — list of `git stash` entries with apply / pop / drop
/// per row, and a "Stash current changes…" button when the working tree is
/// dirty.
struct StashesView: View {
    @Bindable var viewModel: RepositoryViewModel

    @State private var stashSheet = false
    @State private var stashMessage: String = ""
    @State private var dropTarget: Stash?

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    private var hasDirtyChanges: Bool { !viewModel.status.isClean }

    var body: some View {
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
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .sheet(isPresented: $stashSheet) { stashSheetView }
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

    @ViewBuilder
    private var content: some View {
        if viewModel.stashes.isEmpty {
            EmptyState(
                icon: .stash,
                title: "No stashes",
                subtitle: hasDirtyChanges
                    ? "Use \u{201C}Stash changes…\u{201D} to park your work-in-progress."
                    : "When you stash work-in-progress it'll show up here."
            ) { EmptyView() }
        } else {
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.md) {
                    ForEach(viewModel.stashes) { stash in
                        stashRow(stash)
                    }
                }
                .padding(DesignTokens.Spacing.xxxxl)
            }
        }
    }

    @ViewBuilder
    private func stashRow(_ stash: Stash) -> some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Text(stash.reference)
                        .font(AppFont.mono(11.5, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                    Text(String(stash.sha.prefix(7)))
                        .font(AppFont.mono(11, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                }
                Text(stash.subject)
                    .font(AppFont.sans(12.5))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DesignTokens.Spacing.sm) {
                GFButton(title: "Apply", size: .small) {
                    Task { await runApply(stash, drop: false) }
                }
                GFButton(title: "Pop", style: .primary, size: .small) {
                    Task { await runApply(stash, drop: true) }
                }
                OverflowMenu {
                    Button("Apply (keep)")           { Task { await runApply(stash, drop: false) } }
                    Button("Pop (apply + drop)")     { Task { await runApply(stash, drop: true)  } }
                    Divider()
                    Button("Drop…", role: .destructive) { dropTarget = stash }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
        .contextMenu {
            Button("Apply (keep)")       { Task { await runApply(stash, drop: false) } }
            Button("Pop (apply + drop)") { Task { await runApply(stash, drop: true)  } }
            Divider()
            Button("Drop…", role: .destructive) { dropTarget = stash }
            Divider()
            Button("Copy reference") { copyToPasteboard(stash.reference) }
            Button("Copy SHA")       { copyToPasteboard(stash.sha) }
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }

    private var stashSheetView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("Stash current changes").font(AppFont.sans(14, weight: .semibold))
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Message (optional)")
                    .font(AppFont.sans(11, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                GFTextField(placeholder: "WIP: refactor commit graph", text: $stashMessage)
            }
            HStack {
                GFButton(title: "Cancel") { stashSheet = false }
                Spacer()
                GFButton(title: "Stash", style: .primary) {
                    let message = stashMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
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
                }
            }
        }
        .padding(DesignTokens.Spacing.huge).frame(width: 420)
        .background(theme.palette.bg1)
        .appTheme(appState.ui.theme)
    }

    private var dropAlertBinding: Binding<Bool> {
        Binding(get: { dropTarget != nil }, set: { if !$0 { dropTarget = nil } })
    }
}

#if DEBUG
#Preview {
    @Previewable @State var theme = AppTheme()
    StashesView(viewModel: RepositoryViewModel.preview)
        .previewAppState(.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
#endif
