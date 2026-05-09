import SwiftUI
import AppKit

struct StashRow: View {
    let stash: Stash
    let onApply: () -> Void
    let onPop: () -> Void
    let onDrop: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            metadata
            HStack(spacing: DesignTokens.Spacing.sm) {
                GFButton(title: "Apply", size: .small, action: onApply)
                GFButton(title: "Pop", style: .primary, size: .small, action: onPop)
                OverflowMenu {
                    Button("Apply (keep)",       action: onApply)
                    Button("Pop (apply + drop)", action: onPop)
                    Divider()
                    Button("Drop…", role: .destructive, action: onDrop)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
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

    private var metadata: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text(stash.reference)
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
                Text(String(stash.sha.prefix(7)))
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
            }
            Text(stash.subject)
                .font(AppFont.sans(12.5))
                .foregroundStyle(theme.palette.fg1)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 8) {
        ForEach(Stash.previewSamples) { stash in
            StashRow(stash: stash, onApply: {}, onPop: {}, onDrop: {})
        }
    }
    .padding()
    .frame(width: 760)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
