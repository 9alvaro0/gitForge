import SwiftUI

/// Wraps `.dropDestination` for a commit row. Extracted so the row's body
/// stays simple — chained drop modifiers used to push the type-checker past
/// its limit when combined with the rest of the row's modifier stack.
struct RowDropModifier: ViewModifier {
    let enabled: Bool
    let targetSha: String
    /// What the HUD says while a drag hovers this row.
    let intent: BranchDropIntent
    @Binding var isTargeted: Bool
    let onDrop: (DraggedBranch) -> Void

    @Environment(\.branchDropTracker) private var dropTracker

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
                dropTracker?.hover(intent, isOver: hovered)
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
    @Environment(\.branchDropTracker) private var dropTracker

    func body(content: Content) -> some View {
        content
            // Target ring instead of a bounce: the chip stays put under the cursor.
            .overlay {
                RoundedRectangle(cornerRadius: Radius.chip)
                    .strokeBorder(theme.colors.accent, lineWidth: 1.5)
                    .padding(-2)
                    .opacity(hovered ? 1 : 0)
            }
            .animation(DesignTokens.Motion.fast, value: hovered)
            .dropDestination(for: DraggedBranch.self) { items, _ in
                guard let dropped = items.first else { return false }
                // Dropping a branch on its own chip is a no-op.
                guard dropped.name != targetBranchName else { return false }
                onDrop(dropped)
                return true
            } isTargeted: { isHovered in
                hovered = isHovered
                dropTracker?.hover(.branch(name: targetBranchName), isOver: isHovered)
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
        .textRole(.body)
        .foregroundStyle(theme.colors.textPrimary)
        .padding(40)
        .frame(width: 360, height: 80)
        .background(targeted ? theme.colors.accentSoft : theme.colors.bgContent)
        .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(theme.colors.separator, lineWidth: 1))
        .modifier(RowDropModifier(
            enabled: true,
            targetSha: "abc1234",
            intent: .commit(shortSha: "abc1234", subject: "Preview"),
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
        .background(theme.colors.bgContent)
        .appTheme(theme)
}

