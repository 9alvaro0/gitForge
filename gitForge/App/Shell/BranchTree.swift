import Foundation

/// One line of the sidebar branch tree: a folder (a shared `a/` prefix) or a
/// local branch.
nonisolated struct BranchTreeRow: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case folder(path: String, expanded: Bool)
        case branch(GitRef)
    }

    let id: String
    /// Last path component, the text the row shows.
    let name: String
    let depth: Int
    let kind: Kind
    /// The branch is HEAD, or the folder holds it.
    let containsHead: Bool
}

/// Builds the sidebar's local-branch tree (redesign spec §6.1).
nonisolated enum BranchTree {
    /// `feature/a` and `feature/b` group under a `feature` folder. At every
    /// level folders come first, then branches, each in natural,
    /// case-insensitive order. Descendants of a folder whose path is in
    /// `collapsed` are left out.
    static func rows(for refs: [GitRef], collapsed: Set<String>) -> [BranchTreeRow] {
        let entries = refs.filter(\.isLocalBranch).map { ref in
            (parts: ref.name.split(separator: "/").map(String.init), ref: ref)
        }
        var rows: [BranchTreeRow] = []
        append(entries, prefix: "", depth: 0, collapsed: collapsed, into: &rows)
        return rows
    }

    /// Remotes that have at least one branch, sorted.
    static func remoteNames(in refs: [GitRef]) -> [String] {
        let names = refs.compactMap { ref -> String? in
            if case .remoteBranch(let remote) = ref.kind { return remote }
            return nil
        }
        return Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func append(
        _ entries: [(parts: [String], ref: GitRef)],
        prefix: String,
        depth: Int,
        collapsed: Set<String>,
        into rows: inout [BranchTreeRow]
    ) {
        var folders: [String: [(parts: [String], ref: GitRef)]] = [:]
        var leaves: [(name: String, ref: GitRef)] = []
        for entry in entries {
            if entry.parts.count > 1 {
                folders[entry.parts[0], default: []].append((Array(entry.parts.dropFirst()), entry.ref))
            } else if let name = entry.parts.first {
                leaves.append((name, entry.ref))
            }
        }

        for name in folders.keys.sorted(by: naturalOrder) {
            let children = folders[name] ?? []
            let path = prefix + name
            let isCollapsed = collapsed.contains(path)
            rows.append(BranchTreeRow(
                id: "folder:\(path)",
                name: name,
                depth: depth,
                kind: .folder(path: path, expanded: !isCollapsed),
                containsHead: children.contains { $0.ref.isHead }
            ))
            if !isCollapsed {
                append(children, prefix: path + "/", depth: depth + 1, collapsed: collapsed, into: &rows)
            }
        }

        for leaf in leaves.sorted(by: { naturalOrder($0.name, $1.name) }) {
            rows.append(BranchTreeRow(
                id: leaf.ref.id,
                name: leaf.name,
                depth: depth,
                kind: .branch(leaf.ref),
                containsHead: leaf.ref.isHead
            ))
        }
    }

    private static func naturalOrder(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }
}
