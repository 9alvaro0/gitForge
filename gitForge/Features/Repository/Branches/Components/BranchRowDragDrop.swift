import SwiftUI

/// Makes a local-branch row in Branches & Tags draggable and a drop target:
/// dropping one branch on another asks to merge or rebase, like dropping a
/// chip on a chip in History. Rows of other kinds pass through unchanged.
struct BranchRowDragDrop: ViewModifier {
    let ref: GitRef
    let isCurrent: Bool
    /// Nil disables both sides (e.g. previews).
    let onDrop: ((DraggedBranch) -> Void)?

    @State private var hovered = false
    @Environment(\.appTheme) private var theme
    @Environment(\.branchDropTracker) private var dropTracker

    func body(content: Content) -> some View {
        if ref.isLocalBranch, let onDrop {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.row)
                        .strokeBorder(theme.colors.accent, lineWidth: 1.5)
                        .opacity(hovered ? 1 : 0)
                }
                .animation(Motion.fast, value: hovered)
                .draggable(DraggedBranch(name: ref.name, isCurrent: isCurrent, isLocal: true,
                                         sourceSha: ref.targetSha)) {
                    BranchDragGhost(name: ref.displayName, isCurrent: isCurrent)
                        .appTheme(theme)
                }
                .dropDestination(for: DraggedBranch.self) { items, _ in
                    // Dropping a branch on its own row does nothing.
                    guard let dropped = items.first, dropped.name != ref.name else { return false }
                    onDrop(dropped)
                    return true
                } isTargeted: { isOver in
                    hovered = isOver
                    dropTracker?.hover(.branch(name: ref.name), isOver: isOver)
                }
        } else {
            content
        }
    }
}
