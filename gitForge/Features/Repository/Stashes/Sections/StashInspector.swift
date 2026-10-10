import SwiftUI

/// Right-hand side of Stashes: the selected stash's message and metadata,
/// its actions, then its files over the diff (as in the commit inspector).
struct StashInspector: View {
    let stash: Stash
    let store: StashDetailStore
    @Binding var diffMode: DiffPane.ViewMode
    let onApply: () -> Void
    let onPop: () -> Void
    let onDrop: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Spacing.s24)
                .padding(.top, Spacing.s20)
                .padding(.bottom, Spacing.s16)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(theme.colors.separator).frame(height: 1)
            content
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text(stash.subject)
                .textRole(.title)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
            metadata
            HStack(spacing: Spacing.s8) {
                GFButton(title: "Apply", action: onApply)
                    .help("Apply the stash and keep it")
                GFButton(title: "Pop", style: .primary, action: onPop)
                    .help("Apply the stash and drop it")
                GFButton(title: "Drop…", style: .destructive, action: onDrop)
            }
        }
    }

    private var metadata: some View {
        let detail = store.detail
        return Grid(alignment: .leading, horizontalSpacing: Spacing.s16, verticalSpacing: Spacing.s6) {
            metaRow("Branch", detail?.parentBranch ?? "—", mono: true)
            metaRow("Base", detail.map { String($0.parentSha.prefix(7)) } ?? "—", mono: true)
            metaRow("Date", detail?.authorDate.map { preferences.dateDisplayMode.format($0) } ?? "—", mono: false)
            metaRow("Ref", stash.reference, mono: true)
        }
        .skeleton(detail == nil && store.isLoading)
    }

    private func metaRow(_ label: String, _ value: String, mono: Bool) -> some View {
        GridRow {
            Text(label)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textQuaternary)
            Group {
                if mono {
                    Text(value).font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                } else {
                    Text(value).textRole(.callout)
                }
            }
            .foregroundStyle(theme.colors.textPrimary)
            .textSelection(.enabled)
        }
    }

    // MARK: Files and diff

    @ViewBuilder
    private var content: some View {
        if let error = store.error, store.detail == nil {
            EmptyState(icon: .warn, title: "Couldn't load stash", subtitle: error) {
                GFButton(title: "Retry") { Task { await store.load() } }
            }
        } else {
            StashFilesTab(store: store, diffMode: $diffMode)
        }
    }
}
