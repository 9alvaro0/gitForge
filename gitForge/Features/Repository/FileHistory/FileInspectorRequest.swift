import Foundation

/// Opens the File history sheet on one file (`WorkspaceUI.fileInspectorRequest`),
/// on its history or its blame. A fresh `id` each time, so asking again for
/// the same file reopens it.
nonisolated struct FileInspectorRequest: Identifiable, Equatable, Sendable {
    enum Tab: Hashable, Sendable {
        case history
        case blame
    }

    let id = UUID()
    /// The file's path in the repository, as the row that asked showed it.
    let path: String
    var tab: Tab = .history
    /// History: the commit to select, if it touched the file. Blame: the
    /// revision to blame; `nil` blames the working tree.
    var revision: String? = nil
    /// Blame: the line to bring into view.
    var line: Int? = nil

    /// Blame of `path` at `revision` (the working tree when `nil`), with
    /// `line` in view.
    static func blame(_ path: String, at revision: String? = nil, line: Int? = nil) -> FileInspectorRequest {
        FileInspectorRequest(path: path, tab: .blame, revision: revision, line: line)
    }
}

nonisolated extension FileInspectorRequest {
    /// Blame for a line of `sha`'s diff of `path`: a kept or added line at
    /// the commit, a removed one at its first parent, where the file was
    /// `previousPath` if the commit renamed it. `nil` for git's "No newline"
    /// marker.
    static func blame(line: DiffLine, commit sha: String, path: String, previousPath: String?) -> FileInspectorRequest? {
        switch line.kind {
        case .removed:
            guard let number = line.oldLineNumber else { return nil }
            return .blame(previousPath ?? path, at: "\(sha)^", line: number)
        case .added, .context:
            guard let number = line.newLineNumber else { return nil }
            return .blame(path, at: sha, line: number)
        case .noNewline:
            return nil
        }
    }

    /// Blame for a line of the working copy's diff of `path`: a kept or
    /// added line in the working tree, a removed one at HEAD (as
    /// `originalPath` for a staged rename). For the staged side the new
    /// numbers are the index's, close to the working tree's.
    static func blame(line: DiffLine, workingPath path: String, originalPath: String?) -> FileInspectorRequest? {
        switch line.kind {
        case .removed:
            guard let number = line.oldLineNumber else { return nil }
            return .blame(originalPath ?? path, at: "HEAD", line: number)
        case .added, .context:
            guard let number = line.newLineNumber else { return nil }
            return .blame(path, line: number)
        case .noNewline:
            return nil
        }
    }
}
