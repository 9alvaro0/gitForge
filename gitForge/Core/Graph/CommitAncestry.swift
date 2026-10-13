import Foundation

/// History's focus mode: the commits on one line of history.
nonisolated enum CommitAncestry {
    /// `tip` and every commit in `commits` reachable from it through parent
    /// links. Parents outside `commits` (not loaded yet) stop the walk; the
    /// set grows as pages load.
    static func reachable(from tip: String, in commits: [Commit]) -> Set<String> {
        let byId = Dictionary(commits.map { ($0.sha, $0) }, uniquingKeysWith: { first, _ in first })
        guard byId[tip] != nil else { return [] }
        var seen: Set<String> = [tip]
        var stack = [tip]
        while let sha = stack.popLast() {
            for parent in byId[sha]?.parentShas ?? [] where byId[parent] != nil && !seen.contains(parent) {
                seen.insert(parent)
                stack.append(parent)
            }
        }
        return seen
    }
}
