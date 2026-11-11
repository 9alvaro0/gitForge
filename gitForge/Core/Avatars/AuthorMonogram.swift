import Foundation

/// The avatar drawn without any network (#65): an author's initials on a
/// colour picked from their email, so the same person keeps the same colour
/// everywhere and on every launch.
nonisolated enum AuthorMonogram {
    /// Up to two letters: the first letter of the first two words of `name`
    /// ("Ana Pérez" → "AP", "M. Vélez" → "MV", "ana" → "A"). Words without a
    /// letter or digit ("—", "(bot)" keeps its "B") are skipped. With no
    /// usable name, the first letter of the email's local part; "?" when
    /// there's nothing at all.
    static func initials(name: String, email: String = "") -> String {
        let fromName = name
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap(firstLetter)
            .prefix(2)
        if !fromName.isEmpty { return fromName.joined().uppercased() }
        let local = email.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
        return firstLetter(Substring(local))?.uppercased() ?? "?"
    }

    /// The seed the colour hashes: the normalized email when there is one
    /// (two authors with the same initials still differ), else the name.
    static func colorSeed(name: String, email: String) -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? name : normalized
    }

    /// Stable palette slot for `seed`: a plain 31-multiplier hash over its
    /// Unicode scalars, the same on every run (Swift's `hashValue` is
    /// randomly seeded per process, so it can't be used).
    static func paletteIndex(seed: String, count: Int) -> Int {
        var hash = 0
        for scalar in seed.unicodeScalars { hash = (hash &* 31) &+ Int(scalar.value) }
        return paletteIndex(hash: hash, count: count)
    }

    /// `abs(Int.min)` traps; the magnitude doesn't.
    static func paletteIndex(hash: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(hash.magnitude % UInt(count))
    }

    private static func firstLetter(_ word: Substring) -> String? {
        word.first(where: { $0.isLetter || $0.isNumber }).map(String.init)
    }
}
