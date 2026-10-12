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
            .frame(height: Spacing.s8)
            .overlay(
                Rectangle()
                    .fill(theme.colors.strokeControl)
                    .frame(height: 1)
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
            // Dragging is mouse-only; VoiceOver users resize with the
            // adjustable action (VO-↑ / VO-↓) instead.
            .accessibilityElement()
            .accessibilityLabel("Resize pane")
            .accessibilityValue("\(Int(height)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: height = min(height + DesignTokens.Resize.step, maxHeight)
                case .decrement: height = max(height - DesignTokens.Resize.step, minHeight)
                @unknown default: return
                }
                onCommit()
            }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var bottomHeight: CGFloat = 160
    VStack(spacing: 0) {
        Rectangle()
            .fill(theme.colors.bgContent)
            .overlay(
                Text("Top pane (flex)")
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.textSecondary)
            )
        RowDragHandle(height: $bottomHeight, minHeight: 80, maxHeight: 360)
        Rectangle()
            .fill(theme.colors.fillControl)
            .frame(height: bottomHeight)
            .overlay(
                Text("Bottom pane — drag the divider (h=\(Int(bottomHeight)))")
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.textSecondary)
            )
    }
    .frame(width: 600, height: 400)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}
