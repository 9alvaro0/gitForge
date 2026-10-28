import Foundation

/// A pull git refused because local changes were in the way. The view model
/// publishes it instead of a failure; `ShellView` asks whether to discard
/// `files` and run the same pull again.
nonisolated struct PullDiscardRequest: Sendable, Equatable, Identifiable {
    let id = UUID()
    /// The files that lose their local changes: the ones git named, or for a
    /// rebase every tracked change.
    let files: [WorkingCopyFile]
    /// git's rebase refused (any tracked change blocks it) rather than a
    /// merge naming files. Also true for a plain pull that `pull.rebase`
    /// turns into a rebase, so it isn't read off `rebase`.
    let refusedByRebase: Bool
    /// How to run the pull again: the options of the refused one.
    let rebase: Bool
    let ffOnly: Bool

    var title: String {
        files.count == 1
            ? String(localized: "Discard changes to 1 file and pull?")
            : String(localized: "Discard changes to \(files.count) files and pull?")
    }

    /// Why these files, then one per line.
    var message: String {
        let intro = refusedByRebase
            ? String(localized: "Pull and rebase needs every tracked change out of the way. These files will lose their local changes:")
            : String(localized: "The pull would overwrite these files. Their local changes will be lost:")
        return ([intro] + DiscardFileList.lines(files)).joined(separator: "\n")
    }
}
