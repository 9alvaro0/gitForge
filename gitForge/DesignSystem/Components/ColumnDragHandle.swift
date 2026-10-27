import SwiftUI

/// 8pt-wide hit area with a 1pt visible divider centered inside. Drag with
/// the standard column-resize cursor; the bound `width` is clamped between
/// `minWidth` and `maxWidth` while dragging.
///
/// By default the handle controls the column to its LEFT: put it on that
/// column's trailing edge. Set `inverted: true` when it sits at the LEADING
/// edge of the column it resizes — a column anchored to the right, like the
/// History columns after Description or the inspector — and dragging left
/// then widens it. Either way, put the handle on the edge that moves when the
/// column resizes, so the divider follows the pointer.
/// `onCommit` fires on drag-end so callers can defer expensive work
/// (UserDefaults writes) until the user lets go, instead of paying that cost
/// on every frame of the drag. `onDoubleClick` (e.g. fit or reset the column)
/// is also offered to VoiceOver as an action named `doubleClickActionName`.
struct ColumnDragHandle: View {
    @Binding var width: CGFloat
    var minWidth: CGFloat = 40
    var maxWidth: CGFloat = 1200
    var inverted: Bool = false
    var dividerColor: Color?
    var onCommit: () -> Void = {}
    var onDoubleClick: (() -> Void)? = nil
    var doubleClickActionName: String = String(localized: "Reset width")

    @State private var startWidth: CGFloat?
    @Environment(\.appTheme) private var theme

    var body: some View {
        // Color.clear has 0 intrinsic size — fills the row's height set by
        // its sibling Text views. Setting only `.frame(width:)` lets the
        // height stay flexible, so the handle never bloats the row.
        Color.clear
            .frame(width: Spacing.s8)
            .overlay(
                Rectangle()
                    .fill(dividerColor ?? theme.colors.separator)
                    .frame(width: 1)
                    .allowsHitTesting(false)
            )
            .contentShape(.rect)
            .gesture(
                // `.global` keeps translation stable when the handle's frame
                // moves during the drag (which it does, because the column it
                // controls is growing). `.local` produced a feedback loop
                // where the cursor "caught up" with the handle and the gesture
                // appeared reversed. A 1pt minimum leaves plain clicks (and
                // double-clicks) alone instead of rewriting the width.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startWidth ?? width
                        if startWidth == nil { startWidth = width }
                        let delta = inverted ? -value.translation.width : value.translation.width
                        let new = Self.clamped(base + delta, min: minWidth, max: maxWidth)
                        guard new != width else { return }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            width = new
                        }
                    }
                    .onEnded { _ in
                        startWidth = nil
                        onCommit()
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleClick?() })
            .pointerStyle(.columnResize)
            // Dragging is mouse-only; VoiceOver users resize with the
            // adjustable action (VO-↑ / VO-↓) instead. Increment always means
            // "make the controlled column wider", whatever `inverted` says.
            .accessibilityElement()
            .accessibilityLabel("Resize column")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = min(width + LayoutMetrics.resizeStep, maxWidth)
                case .decrement: width = max(width - LayoutMetrics.resizeStep, minWidth)
                @unknown default: return
                }
                onCommit()
            }
            .accessibilityActions {
                if let onDoubleClick {
                    Button(doubleClickActionName, action: onDoubleClick)
                }
            }
    }

    /// `value` within `min...max`; `min` wins when the bounds cross (a cap
    /// that shrank below the column's minimum).
    nonisolated static func clamped(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(value, upper))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var w1: CGFloat = 200
    @Previewable @State var w2: CGFloat = 120
    VStack(spacing: 0) {
        HStack(spacing: 0) {
            Text("ALPHA")
                .textRole(.monoSmall)
                .frame(width: w1, alignment: .leading)
            ColumnDragHandle(width: $w1, minWidth: 80, maxWidth: 400)
            Text("BETA")
                .textRole(.monoSmall)
                .frame(width: w2, alignment: .leading)
            ColumnDragHandle(width: $w2, minWidth: 60, maxWidth: 300)
            Text("GAMMA")
                .textRole(.monoSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.s8)
        .background(theme.colors.bgContent)
        Divider()
        Text("Drag the dividers — w1=\(Int(w1)), w2=\(Int(w2))")
            .textRole(.monoSmall)
            .padding()
        Spacer()
    }
    .frame(width: 700, height: 200)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}
