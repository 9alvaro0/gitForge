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
        VStack(spacing: 0) {
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
                    Task { await viewModel.dropStash(stash) }
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
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.stashes) { stash in
                        stashRow(stash)
                    }
                }
                .padding(18)
            }
        }
    }

    @ViewBuilder
    private func stashRow(_ stash: Stash) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
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
            HStack(spacing: 6) {
                GFButton(title: "Apply", size: .small) {
                    Task { await viewModel.applyStash(stash, drop: false) }
                }
                GFButton(title: "Pop", style: .primary, size: .small) {
                    Task { await viewModel.applyStash(stash, drop: true) }
                }
                OverflowMenu {
                    Button("Apply (keep)")           { Task { await viewModel.applyStash(stash, drop: false) } }
                    Button("Pop (apply + drop)")     { Task { await viewModel.applyStash(stash, drop: true)  } }
                    Divider()
                    Button("Drop…", role: .destructive) { dropTarget = stash }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }

    private var stashSheetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stash current changes").font(AppFont.sans(14, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
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
                            appState.activeToast = ToastMessage(
                                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                                kind: .error
                            )
                        } else {
                            appState.activeToast = ToastMessage(message: "Stashed", kind: .ok)
                        }
                        stashSheet = false
                    }
                }
            }
        }
        .padding(20).frame(width: 420)
        .background(theme.palette.bg1)
        .appTheme(appState.theme)
    }

    private var dropAlertBinding: Binding<Bool> {
        Binding(get: { dropTarget != nil }, set: { if !$0 { dropTarget = nil } })
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    StashesView(viewModel: RepositoryViewModel.preview)
        .environment(AppState.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
