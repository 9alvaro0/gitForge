import SwiftUI

/// Opens the File history sheet on one file (`WorkspaceUI.fileInspectorRequest`).
/// A fresh `id` each time, so asking again for the same file reopens it.
nonisolated struct FileInspectorRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    /// The file's path in the repository, as the row that asked showed it.
    let path: String
    /// The commit to select in the history, if it touched the file.
    var revision: String? = nil
}

/// What a file row's context menu calls to open the File history sheet.
/// `ContentRouter` provides it for the open repository; where it's `nil`
/// (previews, a pull request of another repository) the rows offer nothing.
struct FileInspectorAction {
    let open: @MainActor (FileInspectorRequest) -> Void

    @MainActor
    func callAsFunction(_ request: FileInspectorRequest) {
        open(request)
    }
}

extension EnvironmentValues {
    @Entry var fileInspector: FileInspectorAction? = nil
}

/// The "Show file history" items of a file row's context menu, with the
/// divider before them. Nothing without an action.
struct FileInspectorMenuItems: View {
    let action: FileInspectorAction?
    let path: String
    /// The commit the row belongs to (commit detail), selected in the history.
    var revision: String? = nil

    var body: some View {
        if let action {
            Divider()
            Button("Show file history") {
                action(FileInspectorRequest(path: path, revision: revision))
            }
        }
    }
}
