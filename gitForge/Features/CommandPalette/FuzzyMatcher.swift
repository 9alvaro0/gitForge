import Foundation

/// Where a query's letters fell in a text, and how good the match is.
nonisolated struct FuzzyMatch: Equatable, Sendable {
    let score: Int
    /// Character offsets in the text, for highlighting.
    let indices: [Int]
}

/// ⌘K matching. `match` takes the query's letters in order, however far
/// apart ("che" → Checkout); `substringMatch` takes a word only as an
/// unbroken run. Either way word starts and runs of consecutive letters score
/// higher, longer texts lower, and case and accents are ignored.
nonisolated enum FuzzyMatcher {
    private static let wordStartBonus = 8
    private static let consecutiveBonus = 5

    /// The query's spaces are ignored; its other letters are taken in order,
    /// each at its first place after the previous one.
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

    /// Where `word` appears unbroken in `text` (`act2` in "feature/ACT2-ui"),
    /// or `nil`. The word is taken as typed, spaces included, so callers pass
    /// one word. Scored with `match`'s bonuses, but not quite as `match`
    /// scores the same letters: a point a letter, the consecutive bonus for
    /// each one after the first and less half the text's length, yet the
    /// word-start bonus only for the run's first letter, where `match` gives
    /// it to every letter at a word start (both of "pr" in "PullRequest").
    /// The first run at a word start wins, or else the first run: in
    /// `acme/carousel` the `ca` of "carousel", not the earlier one inside
    /// "acme".
    static func substringMatch(_ word: String, in text: String) -> FuzzyMatch? {
        let needle = word.map(fold)
        guard !needle.isEmpty else { return FuzzyMatch(score: 0, indices: []) }
        let chars = Array(text)
        guard needle.count <= chars.count else { return nil }
        let folded = chars.map(fold)

        var best: Int?
        for start in 0...(chars.count - needle.count)
        where folded[start..<start + needle.count].elementsEqual(needle) {
            if best == nil { best = start }
            if isWordStart(chars, start) {
                best = start
                break
            }
        }
        guard let start = best else { return nil }
        let bonus = isWordStart(chars, start) ? wordStartBonus : 0
        let score = needle.count + bonus + consecutiveBonus * (needle.count - 1) - chars.count / 2
        return FuzzyMatch(score: score, indices: Array(start..<start + needle.count))
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
