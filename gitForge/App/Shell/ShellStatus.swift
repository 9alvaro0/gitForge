import Foundation

/// Text the v2 shell derives from repository state (redesign spec §6.1).
nonisolated enum ShellStatus {
    /// Toolbar subtitle: the branch, then ahead / behind when non-zero.
    static func subtitle(branch: String?, ahead: Int, behind: Int) -> String {
        guard let branch else { return String(localized: "Detached HEAD") }
        var counts: [String] = []
        if ahead > 0 { counts.append("↑\(ahead)") }
        if behind > 0 { counts.append("↓\(behind)") }
        return counts.isEmpty ? branch : "\(branch)  \(counts.joined(separator: " "))"
    }

    /// Tooltip of the Fetch button. Replaces the status bar's "last fetch".
    static func fetchHelp(lastFetch: Date?, now: Date, online: Bool) -> String {
        guard online else { return String(localized: "Offline") }
        guard let lastFetch else { return String(localized: "Fetch from remotes · never fetched") }
        let seconds = max(0, now.timeIntervalSince(lastFetch))
        switch seconds {
        case ..<60:
            return String(localized: "Fetch from remotes · last fetched just now")
        case ..<3_600:
            let minutes = Int(seconds / 60)
            return String(localized: "Fetch from remotes · last fetched \(minutes) min ago")
        case ..<86_400:
            let hours = Int(seconds / 3_600)
            return String(localized: "Fetch from remotes · last fetched \(hours) h ago")
        default:
            let days = Int(seconds / 86_400)
            return String(localized: "Fetch from remotes · last fetched \(days) d ago")
        }
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
