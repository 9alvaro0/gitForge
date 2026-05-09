import SwiftUI

struct StashFileRow: View {
    let file: StashFileChange
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.md) {
                StatusTag(kind: StatusTag.Kind(stashFileStatus: file.status))
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
    init(stashFileStatus: StashFileChange.Status) {
        switch stashFileStatus {
        case .added:        self = .added
        case .modified:     self = .modified
        case .deleted:      self = .deleted
        case .renamed:      self = .renamed
        case .copied:       self = .copied
        case .typeChanged:  self = .modified
        case .other:        self = .modified
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 0) {
        ForEach(StashFileChange.previewSamples) { file in
            StashFileRow(
                file: file,
                isSelected: file.path == StashFileChange.previewSamples.first?.path,
                onSelect: {}
            )
        }
    }
    .padding()
    .frame(width: 480)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
