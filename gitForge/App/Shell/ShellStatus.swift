import Foundation

/// Text the v2 shell derives from repository state (redesign spec §6.1).
nonisolated enum ShellStatus {
    /// Toolbar subtitle: the branch, then ahead / behind when non-zero.
    static func subtitle(branch: String?, ahead: Int, behind: Int) -> String {
        guard let branch else { return "Detached HEAD" }
        var counts: [String] = []
        if ahead > 0 { counts.append("↑\(ahead)") }
        if behind > 0 { counts.append("↓\(behind)") }
        return counts.isEmpty ? branch : "\(branch)  \(counts.joined(separator: " "))"
    }

    /// Tooltip of the Fetch button. Replaces the status bar's "last fetch".
    static func fetchHelp(lastFetch: Date?, now: Date, online: Bool) -> String {
        guard online else { return "Offline" }
        guard let lastFetch else { return "Fetch from remotes · never fetched" }
        let seconds = max(0, now.timeIntervalSince(lastFetch))
        let age: String
        switch seconds {
        case ..<60: age = "just now"
        case ..<3_600: age = "\(Int(seconds / 60)) min ago"
        case ..<86_400: age = "\(Int(seconds / 3_600)) h ago"
        default: age = "\(Int(seconds / 86_400)) d ago"
        }
        return "Fetch from remotes · last fetched \(age)"
    }

    /// Two-letter mark for the repository tile: the first letters of the
    /// first two words (split on non-alphanumerics and camel-case humps),
    /// or the first two characters of a single word. Lowercased.
    static func initials(for name: String) -> String {
        var words: [String] = []
        var current = ""
        for character in name {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current); current = "" }
                continue
            }
            if character.isUppercase, let last = current.last, last.isLowercase {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }

        guard let first = words.first else { return "?" }
        let mark = words.count > 1
            ? String(first.prefix(1)) + String(words[1].prefix(1))
            : String(first.prefix(2))
        return mark.lowercased()
    }
}
