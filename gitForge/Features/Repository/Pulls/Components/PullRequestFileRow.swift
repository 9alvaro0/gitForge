import SwiftUI

struct PullRequestFileRow: View {
    let file: PullRequestFileChange
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.md) {
                StatusTag(kind: StatusTag.Kind(prFileStatus: file.status))
                Text(file.path)
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(isSelected ? theme.palette.fg1 : theme.palette.fg2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if file.additions > 0 {
                    MonoText("+\(file.additions)", color: theme.palette.add)
                }
                if file.deletions > 0 {
                    MonoText("−\(file.deletions)", color: theme.palette.del)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.palette.bg3 : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

extension StatusTag.Kind {
    init(prFileStatus: PullRequestFileChange.Status) {
        switch prFileStatus {
        case .added:    self = .added
        case .modified: self = .modified
        case .deleted:  self = .deleted
        case .renamed:  self = .renamed
        case .copied:   self = .copied
        case .other:    self = .modified
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let samples = PullRequestFileChange.previewSamples
    VStack(spacing: 0) {
        if let first = samples.first {
            PullRequestFileRow(file: first, isSelected: true, onSelect: {})
        }
        ForEach(samples.dropFirst()) { file in
            PullRequestFileRow(file: file, isSelected: false, onSelect: {})
        }
    }
    .padding()
    .frame(width: 480)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
