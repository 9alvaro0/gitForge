import SwiftUI
import AppKit

/// One stash in the list: reference and message. Click opens it in the
/// inspector; the context menu keeps Apply / Pop / Drop at hand.
struct StashRow: View {
    let stash: Stash
    let isSelected: Bool
    let onSelect: () -> Void
    let onApply: () -> Void
    let onPop: () -> Void
    let onDrop: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s8) {
                Image(systemName: "tray")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16)
                Text(stash.subject)
                    .textRole(.body, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(stash.reference)
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.leading, Spacing.s8)
            .padding(.trailing, Spacing.s12)
            .frame(height: theme.density.metrics.rowList)
            .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowFill))
            .contentShape(.rect(cornerRadius: Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(stash.subject), \(stash.reference)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Apply (keep)",       action: onApply)
            Button("Pop (apply + drop)", action: onPop)
            Divider()
            Button("Drop…", role: .destructive, action: onDrop)
            Divider()
            Button("Copy reference") { copyToPasteboard(stash.reference) }
            Button("Copy SHA")       { copyToPasteboard(stash.sha) }
        }
    }

    private var rowFill: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 0) {
        ForEach(Stash.previewSamples) { stash in
            StashRow(stash: stash, isSelected: stash.index == 0,
                     onSelect: {}, onApply: {}, onPop: {}, onDrop: {})
        }
    }
    .padding(Spacing.s6)
    .frame(width: 360)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
