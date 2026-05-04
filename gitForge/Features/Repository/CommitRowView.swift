import SwiftUI

struct CommitRowView: View {
    let commit: Commit
    let isSelected: Bool
    var refs: [GitRef] = []

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(commit.isMerge ? Color.purple : Color.accentColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !refs.isEmpty {
                        ForEach(refs.prefix(4)) { ref in
                            RefBadge(ref: ref)
                        }
                    }
                    Text(commit.subject)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fontWeight(isSelected ? .semibold : .regular)
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
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
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
    VStack(spacing: 0) {
        CommitRowView(
            commit: Commit.previewSamples[0],
            isSelected: true,
            refs: [GitRef.previewSamples[0], GitRef.previewSamples[3]]
        )
        Divider()
        CommitRowView(
            commit: Commit.previewSamples[1],
            isSelected: false,
            refs: [GitRef.previewSamples[1]]
        )
        Divider()
        CommitRowView(commit: Commit.previewSamples[2], isSelected: false)
        Divider()
        CommitRowView(
            commit: Commit.previewSamples[4],
            isSelected: false,
            refs: [GitRef.previewSamples[5]]
        )
    }
    .frame(width: 540)
    .padding()
}
