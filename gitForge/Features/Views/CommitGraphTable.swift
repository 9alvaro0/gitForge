import SwiftUI

/// Commit table with placeholder graph gutter. The actual graph drawing is
/// iterated on top of this scaffold (`CommitGraphCanvas`) at the very end —
/// for now we render the dots only so the rest of the History layout works.
struct CommitGraphTable: View {
    let commits: [Commit]
    let layouts: [GraphRowLayout]
    let refsBySha: [String: [GitRef]]
    let currentBranch: String?
    let selectedSha: Commit.ID?
    let workingCopyDirty: Bool
    let onSelect: (String) -> Void

    @Environment(\.appTheme) private var theme

    private var maxLanes: Int {
        layouts.map(\.totalLanes).max() ?? 1
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if workingCopyDirty {
                    UncommittedRow(maxLanes: maxLanes)
                }
                ForEach(Array(commits.enumerated()), id: \.element.sha) { idx, commit in
                    CommitRow(
                        commit: commit,
                        layout: layouts[safe: idx] ?? .empty,
                        maxLanes: maxLanes,
                        refs: refsBySha[commit.sha] ?? [],
                        currentBranch: currentBranch,
                        isSelected: commit.sha == selectedSha,
                        onSelect: { onSelect(commit.sha) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct UncommittedRow: View {
    let maxLanes: Int
    @Environment(\.appTheme) private var theme
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: 18)
                Rectangle().fill(theme.palette.mod).frame(width: 8, height: 8)
                    .overlay(Rectangle().stroke(theme.palette.mod, lineWidth: 1))
            }
            .frame(width: 110, alignment: .leading)
            HStack(spacing: 8) {
                Circle().fill(theme.palette.mod).frame(width: 8, height: 8)
                Text("Uncommitted changes")
                    .font(AppFont.sans(12.5))
                    .italic()
                    .foregroundStyle(theme.palette.mod)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("").frame(width: 130)
            Text("–").font(AppFont.mono(11, family: theme.monoFont)).foregroundStyle(theme.palette.fg3).frame(width: 80, alignment: .leading)
            Text("now").font(AppFont.mono(11, family: theme.monoFont)).foregroundStyle(theme.palette.fg3).frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(LinearGradient(colors: [theme.palette.mod.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing))
    }
}

private struct CommitRow: View {
    let commit: Commit
    let layout: GraphRowLayout
    let maxLanes: Int
    let refs: [GitRef]
    let currentBranch: String?
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            graphGutter
                .frame(width: 110, alignment: .leading)
            messageColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Avatar(name: commit.authorName, size: 16)
                Text(commit.authorName)
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 130, alignment: .leading)
            Text(commit.shortSha)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: 80, alignment: .leading)
            Text(relativeWhen)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(theme.palette.accent).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    /// Re-uses the existing `GraphColumnView` so lane drawing matches the rest of the app.
    private var graphGutter: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 18)
            GraphColumnView(row: layout, maxLanes: max(maxLanes, 1))
        }
    }

    private var messageColumn: some View {
        HStack(spacing: 8) {
            Text(commit.subject)
                .font(AppFont.sans(12.5))
                .foregroundStyle(theme.palette.fg1)
                .lineLimit(1)
                .truncationMode(.tail)
            ForEach(refs) { ref in
                BranchChip(
                    name: ref.displayName,
                    current: ref.isLocalBranch && ref.name == currentBranch,
                    remote: ref.isRemoteBranch,
                    tag: ref.isTag
                )
            }
        }
    }

    private var rowBackground: Color {
        if isSelected { return theme.palette.accentSoft }
        return .clear
    }

    private var relativeWhen: String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: commit.authorDate, relativeTo: .now)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let vm = RepositoryViewModel.preview
    CommitGraphTable(
        commits: vm.commits,
        layouts: vm.graphLayouts,
        refsBySha: vm.refsBySha,
        currentBranch: vm.currentBranchName,
        selectedSha: vm.commits.first?.sha,
        workingCopyDirty: !vm.status.isClean,
        onSelect: { _ in }
    )
    .frame(width: 920, height: 480)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
