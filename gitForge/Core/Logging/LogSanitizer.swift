import Foundation

/// Scrubs text before it reaches the local log file. Builds on
/// `GitCLI.redacted` (URL userinfo and the account tokens registered with
/// `SecretRedactor`) and adds what a server, a hook or a credential helper
/// could echo that this session never registered: well-known token shapes,
/// `Authorization` / `Bearer` values and `password=`-style pairs. The home
/// folder becomes `~` so the user name doesn't end up in a shared report.
/// Terminal control sequences are dropped so a log line stays one line of
/// plain text.
nonisolated enum LogSanitizer {
    static let mask = "****"

    /// `(pattern, template)` pairs applied in order. Templates keep any
    /// label (`Authorization: `, `password=`) and blank the value.
    private static let rules: [(NSRegularExpression, String)] = {
        let specs: [(String, String)] = [
            // GitHub: classic (ghp_, gho_, ghu_, ghs_, ghr_) and fine-grained.
            (#"\bgh[pousr]_[A-Za-z0-9]{20,}"#, mask),
            (#"\bgithub_pat_[A-Za-z0-9_]{20,}"#, mask),
            // GitLab: glpat-, gloas-, glrt-, glptt-, …
            (#"\bgl[a-z]{2,6}-[A-Za-z0-9_\-]{20,}"#, mask),
            // HTTP auth headers echoed by `GIT_CURL_VERBOSE` / `GIT_TRACE_CURL`.
            (#"(?i)(\b(?:proxy-)?authorization\s*:\s*)(?:(?:basic|bearer|token)\s+)?\S+"#, "$1" + mask),
            (#"(?i)(\bbearer\s+)[A-Za-z0-9._~+/=\-]{8,}"#, "$1" + mask),
            // key=value / key: value pairs.
            (#"(?i)(\b(?:password|passwd|pwd|secret|token|access_token|private_token|client_secret)\s*[=:]\s*)[^\s&"']+"#, "$1" + mask),
        ]
        return specs.compactMap { pattern, template in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
        }
    }()

    /// ANSI escape sequences (`ESC[…m` and friends).
    private static let ansi = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")

    static func sanitize(_ text: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var result = GitCLI.redacted(text)
        result = replace(ansi, in: result, with: "")
        result = String(String.UnicodeScalarView(result.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }))
        for (regex, template) in rules {
            result = replace(regex, in: result, with: template)
        }
        return abbreviatingHome(result, homeDirectory: homeDirectory)
    }

    /// `/Users/alice/src/app` → `~/src/app`, but `/Users/alice2` stays.
    static func abbreviatingHome(_ text: String, homeDirectory: String) -> String {
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        guard home.count > 1, text.contains(home) else { return text }
        let pattern = NSRegularExpression.escapedPattern(for: home) + #"(?=[/\s'"`:;,)\]]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return replace(regex, in: text, with: "~")
    }

    private static func replace(_ regex: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
