import SwiftUI

/// Side-effects flow back through typed callbacks so the row stays
/// independent of `RepositoryViewModel`.
struct ConflictFileRow: View {
    let file: ConflictFile
    let isSelected: Bool
    let absoluteURL: URL
    let onSelect: () -> Void
    let onResolveOurs: () -> Void
    let onResolveTheirs: () -> Void
    let onDiscard: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.md) {
                statusBadge
                Text(file.path)
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(file.resolved ? theme.palette.fg3 : theme.palette.fg1)
                    .strikethrough(file.resolved)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(file.conflicts)")
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(isSelected ? theme.palette.bg4 : .clear))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.sm))
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
    }

    private var statusBadge: some View {
        ZStack {
            Circle().fill((file.resolved ? theme.palette.ok : theme.palette.del).opacity(DesignTokens.Opacity.muted))
            Text(file.resolved ? "✓" : "!")
                .font(.system(size: FontSize.footnote, weight: .bold))
                .foregroundStyle(file.resolved ? theme.palette.ok : theme.palette.del)
        }
        .frame(width: DesignTokens.IconSize.xl, height: DesignTokens.IconSize.xl)
    }

    @ViewBuilder
    private var menu: some View {
        if !file.resolved {
            Button("Resolve using ours") { onResolveOurs() }
            Button("Resolve using theirs") { onResolveTheirs() }
            Button("Discard conflict (revert to HEAD)", role: .destructive) { onDiscard() }
            Divider()
        }
        Button("Open in editor") { NSWorkspace.shared.open(absoluteURL) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([absoluteURL]) }
        Divider()
        Button("Copy path") { copy(file.path) }
        Button("Copy filename") { copy((file.path as NSString).lastPathComponent) }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 0) {
        ForEach(ConflictFile.previewSamples) { file in
            ConflictFileRow(
                file: file,
                isSelected: file.path == ConflictFile.previewSamples.first?.path,
                absoluteURL: URL(fileURLWithPath: "/tmp/\(file.path)"),
                onSelect: {}, onResolveOurs: {}, onResolveTheirs: {}, onDiscard: {}
            )
        }
    }
    .frame(width: 320)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
