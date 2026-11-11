import SwiftUI

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

/// The "Show file history" and "Blame" items of a file row's context menu,
/// with the divider before them. Nothing without an action.
struct FileInspectorMenuItems: View {
    let action: FileInspectorAction?
    let path: String
    /// The commit the row belongs to (commit detail): selected in the
    /// history, and the revision blamed. `nil`: HEAD's history and the
    /// working tree's blame.
    var revision: String? = nil
    /// The row's file was deleted (in that commit, or in the working tree):
    /// there are no lines left to blame there.
    var isDeleted = false

    var body: some View {
        if let action {
            Divider()
            Button("Show file history") {
                action(FileInspectorRequest(path: path, revision: revision))
            }
            Button("Blame") {
                action(.blame(path, at: blameRevision))
            }
        }
    }

    /// A deleted file is blamed as it was just before: at the commit's
    /// parent, or at HEAD for a deletion in the working tree.
    private var blameRevision: String? {
        guard isDeleted else { return revision }
        return revision.map { "\($0)^" } ?? "HEAD"
    }
}
