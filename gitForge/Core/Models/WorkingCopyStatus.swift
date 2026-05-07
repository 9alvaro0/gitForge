import Foundation

nonisolated struct WorkingCopyStatus: Sendable, Equatable {
    let files: [WorkingCopyFile]

    var stagedFiles: [WorkingCopyFile] {
        files.filter(\.isStaged).sorted { $0.path < $1.path }
    }

    var unstagedFiles: [WorkingCopyFile] {
        files.filter(\.isUnstaged).sorted { $0.path < $1.path }
    }

    var hasStagedChanges: Bool { !stagedFiles.isEmpty }
    var isClean: Bool { files.isEmpty }
}
