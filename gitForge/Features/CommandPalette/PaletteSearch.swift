import Foundation

/// ⌘K matching for an item that can be found by more than its label: a pull
/// request is searched by title, repo path, branch, author and number, each
/// word of the query as an unbroken run.
nonisolated enum PaletteSearch {
    /// What an exact number scores: above any fuzzy match.
    static let exactNumberScore = 1_000_000

    /// The number a query is made of when it is only that, optionally behind
    /// a `#` (GitHub) or `!` (GitLab) and surrounded by spaces. Zero and
    /// signed or mixed text are not numbers.
    static func number(in query: String) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = hasReferenceSymbol(trimmed) ? trimmed.dropFirst() : trimmed[...]
        guard isDigits(digits), let value = Int(digits), value > 0 else { return nil }
        return value
    }

    /// How `query` matches an item, or `nil` when it does not.
    ///
    /// - The item's own number, typed alone, is an exact hit with no letters
    ///   to highlight.
    /// - Without keywords this is `FuzzyMatcher.match` on the label.
    /// - With keywords the query splits into words, and each one must appear
    ///   unbroken (`FuzzyMatcher.substringMatch`) in the label or a keyword,
    ///   in any order. Letters spread apart don't count: a pull request's
    ///   title, branch and repo path hold the letters of almost any short
    ///   word. The score adds up every word's best run, so a word at a word
    ///   start in a short field ranks highest, and only the label's letters
    ///   are highlighted.
    static func match(_ query: String, label: String, keywords: [String], number: Int?) -> FuzzyMatch? {
        if let number, number == Self.number(in: query) {
            return FuzzyMatch(score: exactNumberScore, indices: [])
        }
        guard !keywords.isEmpty else { return FuzzyMatcher.match(query, in: label) }

        var score = 0
        var highlighted = Set<Int>()
        for word in query.split(whereSeparator: \.isWhitespace).map({ withoutReferenceSymbol(String($0)) }) {
            let inLabel = FuzzyMatcher.substringMatch(word, in: label)
            let inKeywords = keywords.compactMap { FuzzyMatcher.substringMatch(word, in: $0)?.score }
            guard let best = ([inLabel?.score].compactMap { $0 } + inKeywords).max() else { return nil }
            score += best
            highlighted.formUnion(inLabel?.indices ?? [])
        }
        return FuzzyMatch(score: score, indices: highlighted.sorted())
    }

    /// `#482` and `!482` look for 482; a lone `#` or `!`, or one before
    /// letters, is typed text.
    private static func withoutReferenceSymbol(_ word: String) -> String {
        hasReferenceSymbol(word) && isDigits(word.dropFirst()) ? String(word.dropFirst()) : word
    }

    private static func hasReferenceSymbol(_ text: String) -> Bool {
        text.first == "#" || text.first == "!"
    }

    private static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
