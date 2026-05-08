import Foundation

extension CommitDetail {
    static let preview = CommitDetail(
        commit: Commit.preview,
        fullMessage: """
        feat: render commit graph with lanes

        - SwiftUI Canvas-based graph rendering
        - Lane assignment that handles merges and forks
        - Color palette stable across refresh
        - Aligned with the commit list rows
        """,
        files: CommitFileChange.previewSamples
    )
}
