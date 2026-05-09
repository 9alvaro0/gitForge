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
                .background(theme.palette.bg1)
                .overlay(alignment: edge) {
                    Rectangle()
                        .fill(theme.palette.lineStrong)
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
            HStack(spacing: DesignTokens.Spacing.md) {
                GFIcon(kind: .diff, size: 12, stroke: theme.palette.fg2)
                Text("Show diff pane")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg2)
                Spacer(minLength: 0)
                GFIcon(kind: .arrowU, size: 11, stroke: theme.palette.fg3)
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
        case .detail:
            VStack(spacing: DesignTokens.Spacing.none) {
                GFIcon(kind: .diamond, size: 13, stroke: theme.palette.fg2)
                    .padding(.top, DesignTokens.Spacing.xxl)
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
        kind == .detail ? DesignTokens.Stroke.regular : nil
    }
    private var edgeHeight: CGFloat? {
        kind == .diff ? DesignTokens.Stroke.regular : nil
    }
    private var helpText: String {
        switch kind {
        case .diff:   return "Show the diff pane"
        case .detail: return "Show commit detail"
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
