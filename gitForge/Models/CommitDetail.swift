import Foundation

nonisolated struct CommitDetail: Sendable, Equatable {
    let commit: Commit
    let fullMessage: String
    let files: [CommitFileChange]

    var bodyText: String {
        let trimmed = fullMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstNewline = trimmed.firstIndex(of: "\n") else { return "" }
        let body = trimmed[trimmed.index(after: firstNewline)...]
        return String(body).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
