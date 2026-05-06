import SwiftUI

/// `.gf-detail` — right-side commit detail in the History view.
struct CommitDetailColumn: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel

    @Environment(\.appTheme) private var theme

    private var detail: CommitDetail? { viewModel.detailCache[commit.sha] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            shaLine
            Text(commit.subject)
                .font(AppFont.sans(14))
                .foregroundStyle(theme.palette.fg1)
            metaCard

            if let detail, !detail.bodyText.isEmpty {
                Text(detail.bodyText)
                    .font(AppFont.mono(12, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            filesSection

            actionsSection
        }
        .task(id: commit.sha) {
            _ = await viewModel.detail(for: commit)
        }
    }

    private var shaLine: some View {
        HStack(spacing: 8) {
            GFIcon(kind: .diamond, size: 14, stroke: theme.palette.fg1)
            Text(commit.shortSha)
                .font(AppFont.mono(13, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
            IconButton(.copy) {
                #if canImport(AppKit)
                NSPasteboard.general.declareTypes([.string], owner: nil)
                NSPasteboard.general.setString(commit.sha, forType: .string)
                #endif
            }
        }
    }

    private var metaCard: some View {
        HStack(spacing: 10) {
            Avatar(name: commit.authorName, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.authorName)
                    .font(AppFont.sans(12, weight: .medium))
                    .foregroundStyle(theme.palette.fg1)
                Text(commit.authorEmail)
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
            }
            Spacer()
            Text(relativeWhen)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg2))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }

    @ViewBuilder
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FILES CHANGED")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.fg3)
                Text("\(detail?.files.count ?? 0)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.palette.fg3)
            }
            if let detail {
                VStack(spacing: 1) {
                    ForEach(detail.files) { f in
                        FileMiniRow(file: f, isActive: viewModel.selectedCommitFile == f.path) {
                            viewModel.selectedCommitFile = f.path
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIONS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                GFButton(title: "Revert") { }
                GFButton(title: "Cherry-pick") { }
                GFButton(title: "Reset to here") { }
                GFButton(title: "Create branch") { }
            }
        }
    }

    private var relativeWhen: String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: commit.authorDate, relativeTo: .now)
    }
}

private struct FileMiniRow: View {
    let file: CommitFileChange
    let isActive: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                StatusTag(kind: tagKind)
                Text(file.path)
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(isActive ? theme.palette.bg3 : .clear))
        }
        .buttonStyle(.plain)
    }

    private var tagKind: StatusTag.Kind {
        switch file.status {
        case .added: return .added
        case .modified, .typeChanged: return .modified
        case .deleted: return .deleted
        case .renamed: return .renamed
        case .copied: return .copied
        case .unmerged: return .unmerged
        case .unknown: return .modified
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommitDetailColumn(commit: Commit.preview, viewModel: RepositoryViewModel.preview)
        .frame(width: DesignTokens.Detail.panelWidth, height: 720)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
