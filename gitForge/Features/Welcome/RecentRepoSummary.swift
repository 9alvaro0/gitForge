import Foundation

/// Branch and state of a recent repository, as Welcome lists it.
nonisolated struct RecentRepoSummary: Equatable, Sendable {
    let branch: String?
    let changed: Int
    let ahead: Int
    let behind: Int

    /// Changes win over ahead/behind: they're what the user would lose.
    var label: String {
        if changed > 0 { return "\(changed) changed" }
        switch (ahead, behind) {
        case (0, 0): return "Clean"
        case (_, 0): return "↑ \(ahead) ahead"
        case (0, _): return "↓ \(behind) behind"
        default: return "↑\(ahead) ↓\(behind)"
        }
    }

    /// Parses `git status --porcelain=v1 --branch`.
    static func parse(_ output: String) -> RecentRepoSummary {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard let header = lines.first, header.hasPrefix("## ") else {
            return RecentRepoSummary(branch: nil, changed: lines.count, ahead: 0, behind: 0)
        }
        let info = header.dropFirst(3)
        let changed = lines.count - 1
        if info.hasPrefix("HEAD (no branch)") {
            return RecentRepoSummary(branch: nil, changed: changed, ahead: 0, behind: 0)
        }
        if info.hasPrefix("No commits yet on ") {
            return RecentRepoSummary(branch: String(info.dropFirst("No commits yet on ".count)), changed: changed,
                                     ahead: 0, behind: 0)
        }
        let branchPart = info.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        let branch = branchPart.components(separatedBy: "...").first ?? branchPart
        return RecentRepoSummary(branch: branch, changed: changed,
                                 ahead: count("ahead", in: info), behind: count("behind", in: info))
    }

    private static func count(_ word: String, in info: Substring) -> Int {
        guard let open = info.firstIndex(of: "["), let close = info.lastIndex(of: "]") else { return 0 }
        for part in info[info.index(after: open)..<close].split(separator: ",") {
            let pieces = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
            if pieces.count == 2, pieces[0] == word { return Int(pieces[1]) ?? 0 }
        }
        return 0
    }
}
