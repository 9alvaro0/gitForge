import SwiftUI

/// 8pt-wide hit area with a 1pt visible divider centered inside. Drag with
/// the standard column-resize cursor; the bound `width` is clamped between
/// `minWidth` and `maxWidth` while dragging.
///
/// By default each handle controls the column to its LEFT — neighbours stay
/// put, like every native table on macOS. Set `inverted: true` when the
/// handle sits at the LEADING edge of the column it resizes (e.g. the right
/// detail panel in History): drag right then shrinks it instead of growing it.
/// `onCommit` fires on drag-end so callers can defer expensive work
/// (UserDefaults writes) until the user lets go, instead of paying that cost
/// on every frame of the drag.
struct ColumnDragHandle: View {
    @Binding var width: CGFloat
    var minWidth: CGFloat = 40
    var maxWidth: CGFloat = 1200
    var inverted: Bool = false
    var dividerColor: Color?
    var onCommit: () -> Void = {}

    @State private var startWidth: CGFloat?
    @Environment(\.appTheme) private var theme

    var body: some View {
        // Color.clear has 0 intrinsic size — fills the row's height set by
        // its sibling Text views. Setting only `.frame(width:)` lets the
        // height stay flexible, so the handle never bloats the row.
        Color.clear
            .frame(width: DesignTokens.Spacing.md)
            .overlay(
                Rectangle()
                    .fill(dividerColor ?? theme.palette.line)
                    .frame(width: DesignTokens.Stroke.regular)
                    .allowsHitTesting(false)
            )
            .contentShape(.rect)
            .gesture(
                // `.global` keeps translation stable when the handle's frame
                // moves during the drag (which it does, because the column it
                // controls is growing). `.local` produced a feedback loop
                // where the cursor "caught up" with the handle and the gesture
                // appeared reversed.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startWidth ?? width
                        if startWidth == nil { startWidth = width }
                        let delta = inverted ? -value.translation.width : value.translation.width
                        let new = base + delta
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            width = min(max(minWidth, new), maxWidth)
                        }
                    }
                    .onEnded { _ in
                        startWidth = nil
                        onCommit()
                    }
            )
            .pointerStyle(.columnResize)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var w1: CGFloat = 200
    @Previewable @State var w2: CGFloat = 120
    VStack(spacing: DesignTokens.Spacing.none) {
        HStack(spacing: DesignTokens.Spacing.none) {
            Text("ALPHA")
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .frame(width: w1, alignment: .leading)
            ColumnDragHandle(width: $w1, minWidth: 80, maxWidth: 400)
            Text("BETA")
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .frame(width: w2, alignment: .leading)
            ColumnDragHandle(width: $w2, minWidth: 60, maxWidth: 300)
            Text("GAMMA")
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(theme.palette.bg2)
        Divider()
        Text("Drag the dividers — w1=\(Int(w1)), w2=\(Int(w2))")
            .font(AppFont.mono(11, family: theme.monoFont))
            .padding()
        Spacer()
    }
    .frame(width: 700, height: 200)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
