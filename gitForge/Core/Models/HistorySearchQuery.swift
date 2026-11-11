import Foundation

/// A History search that git runs over the whole log, not only the loaded pages (#62).
/// Each non-empty field is one criterion; criteria combine with AND.
nonisolated struct HistorySearchQuery: Sendable, Equatable, Hashable {
    /// The criteria the filters bar offers, in the order its chips show.
    enum Field: String, Sendable, CaseIterable, Identifiable {
        /// `--grep`: the commit message, subject and body.
        case message
        /// `--author`: "Name <email>".
        case author
        /// `-S` (a string added or removed) or `-G` (a regex in a changed line).
        case content
        /// `-- <pathspec>`: commits that touch the path.
        case path

        var id: String { rawValue }
    }

    var message = ""
    var author = ""
    var content = ""
    /// `content` is an extended regex matched against changed lines (`-G`)
    /// instead of a string whose number of occurrences changed (`-S`).
    var contentIsRegex = false
    var path = ""

    subscript(field: Field) -> String {
        get {
            switch field {
            case .message: message
            case .author: author
            case .content: content
            case .path: path
            }
        }
        set {
            switch field {
            case .message: message = newValue
            case .author: author = newValue
            case .content: content = newValue
            case .path: path = newValue
            }
        }
    }

    /// The query git runs: each field without surrounding whitespace, the regex flag only
    /// when there is content for it. Two queries that run the same search are equal.
    var normalized: HistorySearchQuery {
        func trim(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
        let content = trim(content)
        return HistorySearchQuery(message: trim(message), author: trim(author), content: content,
                                  contentIsRegex: contentIsRegex && !content.isEmpty, path: trim(path))
    }

    /// No criterion has text: there is nothing to search for.
    var isEmpty: Bool {
        Field.allCases.allSatisfy { self[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
