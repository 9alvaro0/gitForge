import SwiftUI

struct CommitRowView: View {
    let commit: Commit
    let isSelected: Bool

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

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fontWeight(isSelected ? .semibold : .regular)
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

#Preview {
    VStack(spacing: 0) {
        CommitRowView(commit: Commit.previewSamples[0], isSelected: true)
        Divider()
        CommitRowView(commit: Commit.previewSamples[1], isSelected: false)
        Divider()
        CommitRowView(commit: Commit.previewSamples[2], isSelected: false)
    }
    .frame(width: 480)
    .padding()
}
