import Foundation

extension WorkingCopyStatus {
    static let preview = WorkingCopyStatus(files: [
        WorkingCopyFile(path: "gitForge/Features/Repository/CommitLogView.swift", stagedStatus: .modified, unstagedStatus: .unmodified, originalPath: nil),
        WorkingCopyFile(path: "gitForge/Models/Commit.swift", stagedStatus: .added, unstagedStatus: .unmodified, originalPath: nil),
        WorkingCopyFile(path: "gitForge/App/AppState.swift", stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil),
        WorkingCopyFile(path: "README.md", stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil),
        WorkingCopyFile(path: "gitForge/Features/NewView.swift", stagedStatus: .unmodified, unstagedStatus: .untracked, originalPath: nil),
    ])
}
