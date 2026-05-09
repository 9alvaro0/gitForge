import SwiftUI

/// Wraps `.dropDestination` for a commit row. Extracted so the row's body
/// stays simple — chained drop modifiers used to push the type-checker past
/// its limit when combined with the rest of the row's modifier stack.
struct RowDropModifier: ViewModifier {
    let enabled: Bool
    let targetSha: String
    @Binding var isTargeted: Bool
    let onDrop: (DraggedBranch) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: DraggedBranch.self) { items, _ in
                guard let dropped = items.first else { return false }
                // Drop on the row the chip already lives on is a no-op — skip
                // the dialog so the user doesn't see a confirm for nothing.
                guard dropped.sourceSha != targetSha else { return false }
                onDrop(dropped)
                return true
            } isTargeted: { hovered in
                isTargeted = hovered
            }
        } else {
            content
        }
    }
}

/// Drop target for chip→chip drops (merge / rebase). The target chip's
/// `dropDestination` wins over the row's because it's the innermost handler
/// — that's the GitKraken-style "drop on the chip = pick a branch action".
struct ChipDropModifier: ViewModifier {
    let targetBranchName: String
    let targetSha: String
    let onDrop: (DraggedBranch) -> Void

    @State private var hovered = false
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered ? 1.06 : 1.0)
            .shadow(color: hovered ? theme.palette.accent.opacity(0.45) : .clear, radius: 4)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .dropDestination(for: DraggedBranch.self) { items, _ in
                guard let dropped = items.first else { return false }
                // Dropping a branch on its own chip is a no-op.
                guard dropped.name != targetBranchName else { return false }
                onDrop(dropped)
                return true
            } isTargeted: { isHovered in
                hovered = isHovered
            }
    }
}

/// Safe subscript so call sites like `layouts[safe: idx] ?? .empty` can
/// degrade gracefully if the auxiliary array trails the primary one by a
/// render tick (e.g. graph layouts following commit-list mutations).
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("RowDropModifier — drop target") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var targeted = false
    Text("Drag a DraggedBranch onto me")
        .font(AppFont.sans(12))
        .foregroundStyle(theme.palette.fg1)
        .padding(40)
        .frame(width: 360, height: 80)
        .background(targeted ? theme.palette.accent.opacity(DesignTokens.Opacity.subtle) : theme.palette.bg1)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.palette.line, lineWidth: 1))
        .modifier(RowDropModifier(
            enabled: true,
            targetSha: "abc1234",
            isTargeted: $targeted,
            onDrop: { _ in }
        ))
        .appTheme(theme)
}

#Preview("ChipDropModifier — drop target") {
    @Previewable @State var theme = AppTheme()
    BranchChip(name: "main", current: true, remote: false, tag: false, hasRemoteCounterpart: false)
        .modifier(ChipDropModifier(
            targetBranchName: "main",
            targetSha: "abc1234",
            onDrop: { _ in }
        ))
        .padding(40)
        .background(theme.palette.bg1)
        .appTheme(theme)
}

