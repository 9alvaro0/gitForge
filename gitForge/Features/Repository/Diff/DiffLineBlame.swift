import SwiftUI

/// "Blame this line" on a diff row. `DiffPane` puts it in its rows'
/// environment when its host offers blame (`DiffPane.onBlameLine`).
struct DiffLineBlameAction {
    let open: @MainActor (DiffLine) -> Void
}

extension EnvironmentValues {
    @Entry var diffLineBlame: DiffLineBlameAction? = nil
}

/// The row's context menu with "Blame this line", when the pane offers it.
struct DiffLineBlameMenu: ViewModifier {
    let line: DiffLine?

    @Environment(\.diffLineBlame) private var blame

    func body(content: Content) -> some View {
        if let blame, let line, line.kind != .noNewline {
            content.contextMenu {
                Button("Blame this line") { blame.open(line) }
            }
        } else {
            content
        }
    }
}
