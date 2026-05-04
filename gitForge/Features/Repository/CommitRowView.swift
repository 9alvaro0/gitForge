import SwiftUI

struct CommitRowView: View {
    let commit: Commit
    let isSelected: Bool
    var refs: [GitRef] = []
    var graphRow: GraphRowLayout?
    var graphMaxLanes: Int = 1
    var hoveredBranchId: Int? = nil
    var onHoverChanged: (Bool) -> Void = { _ in }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var dimRow: Bool {
        guard let hovered = hoveredBranchId, let mine = graphRow?.commitBranchId else { return false }
        return hovered != mine
    }

    private var accentColor: Color {
        guard let row = graphRow else { return .accentColor }
        return GraphColumnView.color(for: row.commitBranchId)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            if let row = graphRow {
                GraphColumnView(
                    row: row,
                    maxLanes: graphMaxLanes,
                    hoveredBranchId: hoveredBranchId
                )
                .frame(height: 60)
            } else {
                Circle()
                    .fill(commit.isMerge ? Color.purple : Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.horizontal, 8)
            }

            AuthorAvatar(name: commit.authorName, email: commit.authorEmail, size: 26)
                .opacity(dimRow ? 0.35 : 1)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(commit.subject)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if !refs.isEmpty {
                        ForEach(refs.prefix(4)) { ref in
                            RefBadge(ref: ref)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Text(commit.shortSha)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(commit.authorName)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(Self.relative.localizedString(for: commit.authorDate, relativeTo: .now))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .opacity(dimRow ? 0.4 : 1)
            .padding(.leading, 4)
            Spacer(minLength: 0)
        }
        .frame(height: 60)
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 3)
            }
        }
        .onHover { onHoverChanged($0) }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            accentColor.opacity(0.18)
        } else {
            Color.clear
        }
    }
}

private struct RefBadge: View {
    let ref: GitRef

    private var background: Color {
        switch ref.kind {
        case .localBranch where ref.isHead: .green
        case .localBranch: .blue
        case .remoteBranch: .gray
        case .tag: .yellow
        }
    }

    private var iconName: String {
        switch ref.kind {
        case .localBranch where ref.isHead: "checkmark.circle.fill"
        case .localBranch: "arrow.triangle.branch"
        case .remoteBranch: "cloud"
        case .tag: "tag.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 9))
            Text(ref.displayName)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background, in: Capsule())
    }
}

#Preview {
    let vm = RepositoryViewModel.preview
    VStack(spacing: 0) {
        ForEach(Array(vm.commits.enumerated()), id: \.element.id) { index, commit in
            CommitRowView(
                commit: commit,
                isSelected: commit.id == vm.selectedCommitId,
                refs: vm.refsBySha[commit.sha] ?? [],
                graphRow: vm.graphLayouts[safe: index],
                graphMaxLanes: vm.graphMaxLanes
            )
            Divider()
        }
    }
    .frame(width: 720)
    .padding()
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
