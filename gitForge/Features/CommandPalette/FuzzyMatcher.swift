import Foundation

/// Where a query's letters fell in a text, and how good the match is.
nonisolated struct FuzzyMatch: Equatable, Sendable {
    let score: Int
    /// Character offsets in the text, for highlighting.
    let indices: [Int]
}

/// ⌘K matching: the query's letters must appear in the text in order
/// ("che" → Checkout). Word starts and runs of consecutive letters score
/// higher, longer texts lower. Case, accents and the query's spaces are
/// ignored.
nonisolated enum FuzzyMatcher {
    private static let wordStartBonus = 8
    private static let consecutiveBonus = 5

    static func match(_ query: String, in text: String) -> FuzzyMatch? {
        let needle = query.filter { !$0.isWhitespace }.map(fold)
        guard !needle.isEmpty else { return FuzzyMatch(score: 0, indices: []) }
        let chars = Array(text)
        guard needle.count <= chars.count else { return nil }

        var indices: [Int] = []
        var score = 0
        var next = 0
        for (offset, ch) in chars.enumerated() where next < needle.count {
            guard fold(ch) == needle[next] else { continue }
            score += 1
            if isWordStart(chars, offset) { score += wordStartBonus }
            if let last = indices.last, last == offset - 1 { score += consecutiveBonus }
            indices.append(offset)
            next += 1
        }
        guard next == needle.count else { return nil }
        return FuzzyMatch(score: score - chars.count / 2, indices: indices)
    }

    private static func fold(_ ch: Character) -> String {
        String(ch).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func isWordStart(_ chars: [Character], _ offset: Int) -> Bool {
        guard offset > 0 else { return true }
        let previous = chars[offset - 1]
        if !(previous.isLetter || previous.isNumber) { return true }
        return previous.isLowercase && chars[offset].isUppercase
    }
}
