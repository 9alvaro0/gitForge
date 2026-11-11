import Foundation

/// One "Only commits by …" request: its own identity, so asking twice for
/// the same author (after clearing the field) applies it again.
nonisolated struct AuthorFilterRequest: Equatable, Sendable {
    let id = UUID()
    let author: CommitAuthor
}

/// How History's filter field narrows the log to one author until git-backed
/// search (#62) has its Author field.
nonisolated enum HistoryAuthorFilter {
    /// The email when there is one, the most precise thing the field matches
    /// (a name can also appear in subjects); otherwise the name.
    static func searchText(for author: CommitAuthor) -> String {
        let email = author.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? author.name.trimmingCharacters(in: .whitespacesAndNewlines) : email
    }
}
