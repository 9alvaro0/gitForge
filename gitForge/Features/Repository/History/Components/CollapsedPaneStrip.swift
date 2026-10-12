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
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 9.6, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text("Show diff pane")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up")
                    .font(.system(size: 8.8, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 11, height: 11)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
        case .detail:
            VStack(spacing: 0) {
                Image(systemName: "diamond")
                    .font(.system(size: 10.4, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 13, height: 13)
                    .accessibilityHidden(true)
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
