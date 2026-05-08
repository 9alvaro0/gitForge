import Foundation

extension CommitFileChange {
    static let previewSamples: [CommitFileChange] = [
        CommitFileChange(path: "gitForge/Features/Repository/CommitLogView.swift", status: .added),
        CommitFileChange(path: "gitForge/Features/Repository/RepositoryView.swift", status: .modified),
        CommitFileChange(path: "gitForge/Features/ContentView.swift", status: .deleted),
        CommitFileChange(
            path: "gitForge/Models/Commit.swift",
            status: .renamed(from: "gitForge/Models/CommitModel.swift")
        ),
    ]
}
