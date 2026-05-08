import SwiftUI

/// Horizontal divider you drag vertically to resize the height of the pane
/// BELOW the handle (e.g. the diff pane below the History table). Drag up =
/// pane grows, drag down = pane shrinks.
struct RowDragHandle: View {
    @Binding var height: CGFloat
    var minHeight: CGFloat = 60
    var maxHeight: CGFloat = 800
    var onCommit: () -> Void = {}

    @State private var startHeight: CGFloat?
    @Environment(\.appTheme) private var theme

    var body: some View {
        Color.clear
            .frame(height: DesignTokens.Spacing.md)
            .overlay(
                Rectangle()
                    .fill(theme.palette.lineStrong)
                    .frame(height: DesignTokens.Stroke.regular)
                    .allowsHitTesting(false)
            )
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startHeight ?? height
                        if startHeight == nil { startHeight = height }
                        // Handle is at the TOP of the resizable pane: drag up
                        // (negative dy) = pane gets taller.
                        let new = base - value.translation.height
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            height = min(max(minHeight, new), maxHeight)
                        }
                    }
                    .onEnded { _ in
                        startHeight = nil
                        onCommit()
                    }
            )
            .pointerStyle(.rowResize)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var bottomHeight: CGFloat = 160
    VStack(spacing: DesignTokens.Spacing.none) {
        Rectangle()
            .fill(theme.palette.bg2)
            .overlay(
                Text("Top pane (flex)")
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
            )
        RowDragHandle(height: $bottomHeight, minHeight: 80, maxHeight: 360)
        Rectangle()
            .fill(theme.palette.bg3)
            .frame(height: bottomHeight)
            .overlay(
                Text("Bottom pane — drag the divider (h=\(Int(bottomHeight)))")
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
            )
    }
    .frame(width: 600, height: 400)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
