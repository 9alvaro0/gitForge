import SwiftUI

/// "Uncommitted changes" row pinned to the top of the log when the working
/// tree is dirty. Mirrors the column layout of a real `CommitRow` so the
/// graph gutter and column boundaries line up, and behaves like a row — a
/// single tap selects it (host wires the click into the working-copy file
/// list + diff pane), and a double tap can be routed elsewhere if needed.
struct UncommittedRow: View {
    let rowHeight: CGFloat
    let gutterWidth: CGFloat
    let columns: ResizableTableModel
    let isSelected: Bool
    let onSelect: () -> Void
    var onDoubleClick: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            HStack(spacing: DesignTokens.Spacing.none) {
                Spacer().frame(width: DesignTokens.IconSize.xl)
                Rectangle().fill(theme.palette.mod).frame(width: DesignTokens.Spacing.md, height: DesignTokens.Spacing.md)
                    .overlay(Rectangle().stroke(theme.palette.mod, lineWidth: DesignTokens.Stroke.regular))
            }
            .frame(width: gutterWidth, alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Color.clear.frame(width: columns.width("branchTag"))
            Color.clear.frame(width: DesignTokens.Spacing.md)
            HStack(spacing: DesignTokens.Spacing.md) {
                Circle().fill(theme.palette.mod).frame(width: DesignTokens.Spacing.md, height: DesignTokens.Spacing.md)
                Text("Uncommitted changes")
                    .font(AppFont.sans(12.5))
                    .italic()
                    .foregroundStyle(theme.palette.mod)
            }
            .frame(width: columns.width("message"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Color.clear.frame(width: columns.width("author"))
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text("–")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("sha"), alignment: .leading)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Text("now")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: columns.width("when"), alignment: .trailing)
            Color.clear.frame(width: DesignTokens.Spacing.md)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .frame(height: rowHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(theme.palette.accent).frame(width: 2) }
        }
        .contentShape(.rect)
        .onTapGesture(count: 2) { onDoubleClick?() }
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Uncommitted changes")
        .accessibilityAddTraits(.isButton)
    }

    private var rowBackground: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(theme.palette.accentSoft)
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [theme.palette.mod.opacity(DesignTokens.Opacity.faint), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel(
        id: "history.uncommitted.preview",
        columns: [
            (id: "graph",     defaultWidth: 110, minWidth: 80),
            (id: "branchTag", defaultWidth: 220, minWidth: 80),
            (id: "message",   defaultWidth: 480, minWidth: 240),
            (id: "author",    defaultWidth: 130, minWidth: 80),
            (id: "sha",       defaultWidth: 80,  minWidth: 60),
            (id: "when",      defaultWidth: 70,  minWidth: 50),
        ]
    )
    VStack(spacing: 0) {
        UncommittedRow(rowHeight: 36, gutterWidth: 110, columns: columns, isSelected: false, onSelect: {})
        UncommittedRow(rowHeight: 36, gutterWidth: 110, columns: columns, isSelected: true, onSelect: {})
    }
    .frame(width: 1100)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
