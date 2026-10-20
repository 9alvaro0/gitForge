import SwiftUI

/// Strip shown when the diff pane or the detail column has been collapsed.
/// Click anywhere to expand. Two flavours:
///   • `.diff`   — horizontal strip pinned to the bottom of the graph column
///   • `.detail` — vertical strip pinned to the right edge of the workspace
struct CollapsedPaneStrip: View {
    enum Kind {
        case diff
        case detail
    }

    let kind: Kind
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            content
                .background(theme.colors.bgElevated)
                .overlay(alignment: edge) {
                    Rectangle()
                        .fill(theme.colors.strokeControl)
                        .frame(width: edgeWidth, height: edgeHeight)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .diff:
            HStack(spacing: Spacing.s8) {
                SymbolGlyph("square.and.pencil", size: 12)
                    .foregroundStyle(theme.colors.textSecondary)
                Text("Show diff pane")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer(minLength: 0)
                SymbolGlyph("arrow.up", size: 11)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
        case .detail:
            VStack(spacing: 0) {
                SymbolGlyph("diamond", size: 13)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.top, Spacing.s12)
                Spacer(minLength: 0)
            }
            .frame(width: 32)
            .frame(maxHeight: .infinity)
        }
    }

    private var edge: Alignment {
        switch kind {
        case .diff:   return .top
        case .detail: return .leading
        }
    }
    private var edgeWidth: CGFloat? {
        kind == .detail ? 1 : nil
    }
    private var edgeHeight: CGFloat? {
        kind == .diff ? 1 : nil
    }
    private var helpText: String {
        switch kind {
        case .diff:   return String(localized: "Show the diff pane")
        case .detail: return String(localized: "Show commit detail")
        }
    }
}

#Preview("Diff strip") {
    @Previewable @State var theme = AppTheme()
    CollapsedPaneStrip(kind: .diff, action: {})
        .frame(width: 720)
        .appTheme(theme)
}

#Preview("Detail strip") {
    @Previewable @State var theme = AppTheme()
    CollapsedPaneStrip(kind: .detail, action: {})
        .frame(height: 360)
        .appTheme(theme)
}
