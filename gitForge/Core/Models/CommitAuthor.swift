import Foundation

/// Who wrote a commit, as git records it. "Only commits by …" (#65) and the
/// avatars key on it.
nonisolated struct CommitAuthor: Sendable, Hashable {
    let name: String
    let email: String

    /// The email the avatars and the colour key on: trimmed and lowercased,
    /// since git keeps whatever case the author typed.
    var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The name, or the email when the commit has no name; what VoiceOver reads.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? email : trimmed
    }
}

extension Commit {
    nonisolated var author: CommitAuthor { CommitAuthor(name: authorName, email: authorEmail) }
}
