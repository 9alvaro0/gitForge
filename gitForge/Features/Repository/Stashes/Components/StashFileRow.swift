import SwiftUI

struct StashFileRow: View {
    let file: StashFileChange
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    private var directory: String {
        let dir = (file.path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }
    private var fileName: String { (file.path as NSString).lastPathComponent }

    private var rowFill: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s8) {
                StatusTag(kind: StatusTag.Kind(stashFile: file.status))
                // Folder dim, file name bright: the name is what the eye scans.
                Text("\(Text(directory).foregroundStyle(theme.colors.textQuaternary))\(Text(fileName).foregroundStyle(theme.colors.textPrimary))")
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if file.additions > 0 {
                    Text("+\(file.additions)").foregroundStyle(theme.colors.add)
                        .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                }
                if file.deletions > 0 {
                    Text("−\(file.deletions)").foregroundStyle(theme.colors.del)
                        .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                }
            }
            .padding(.horizontal, Spacing.s8)
            .frame(height: theme.density.metrics.rowFile)
            .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(rowFill))
            .contentShape(.rect(cornerRadius: Radius.controlSmall))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(file.path), \(file.additions) additions, \(file.deletions) deletions")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
