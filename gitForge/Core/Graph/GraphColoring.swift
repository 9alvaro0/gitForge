import Foundation

/// Stage 5 of the layout: the colour role of every line owner (§5.4).
///
/// The roles are meaning, not hues: the view maps `.head` to the accent,
/// `.main` and `.develop` to their trunk colours and `.pool(i)` to the i-th
/// colour of the palette for the current accent.
nonisolated struct GraphColoring: Sendable {
    var roleOfOwner: [GraphOwner: GraphColorRole]

    /// `.neutral` for an owner the graph never saw.
    func role(_ owner: GraphOwner) -> GraphColorRole { roleOfOwner[owner] ?? .neutral }

    /// Gives a role to every owner of a drawn line or of a row's colour.
    ///
    /// **Fixed roles** come from what the owner is:
    /// - HEAD's branch, or a detached HEAD, is `.head`.
    /// - Rank 0 (`main`, `master`, `trunk`) is `.main`, rank 1 (`develop`, `dev`) is `.develop`.
    ///   A remote trunk has the rank of the trunk it stands in for (§3.1), so the same roles.
    /// - A stash is `.stash`.
    /// - Any other remote follows the local branch whose upstream it is, when that
    ///   branch has a role to give; otherwise it is an ordinary owner. A remote
    ///   trunk follows no one, whatever tracks it.
    ///
    /// **The rest take a palette index**, one stretch of line at a time. A stretch
    /// is a drawn line in its column with a single colour owner; HEAD's line is
    /// split wherever its colour owner changes (§5.4). Stretches are visited by
    /// first row, and an owner without a role takes the least used index among
    /// those that no stretch in the next column on either side already shows
    /// within two rows. It keeps that index on all its stretches. When every
    /// index is taken around it, the least used of all wins.
    ///
    /// The search stops at the end of the page the stretch starts on, so loading
    /// the next page does not change a colour already drawn (§3.9), except when
    /// a local branch's tip loads on a later page than its upstream's: the remote
    /// then changes to follow the branch's colour (deferred to phase G3). The cost
    /// of clipping at the page end is accepted: a line on one page may share its
    /// colour with a neighbour that starts on the next page. Later stretches
    /// still see the earlier ones around them.
    ///
    /// Tracks are not stretches: only drawn lines count as neighbours.
    static func assign(_ input: GraphInput, lines: GraphLines, columns: GraphColumns) -> GraphColoring {
        let headBranch = input.headBranch
        let owners = Set(lines.lines.map(\.owner)).union(lines.colorOwnerOfRow)

        var roles: [GraphOwner: GraphColorRole] = [:]
        for owner in owners {
            roles[owner] = fixedRole(of: owner, headBranch: headBranch, input: input)
        }

        // A remote's role is its local branch's. A fixed one is known now; a palette
        // index is copied when the branch takes it.
        let localOfRemote = remoteFollowers(input, owners: owners, headBranch: headBranch)
        var followers: [GraphOwner: [GraphOwner]] = [:]
        for (remote, local) in localOfRemote {
            if let fixed = fixedRole(of: local, headBranch: headBranch, input: input) {
                roles[remote] = fixed
            } else {
                followers[local, default: []].append(remote)
            }
        }

        let paletteSize = input.paletteSize
        guard paletteSize > 0 else { return GraphColoring(roleOfOwner: roles) }

        let headOwner = headBranch.map(GraphOwner.branch) ?? .head
        let stretches = makeStretches(input, lines: lines, columns: columns, headOwner: headOwner)
        let neighbours = StretchesByColumn(stretches)
        var usage = Array(repeating: 0, count: paletteSize)
        for stretch in stretches.sorted(by: { ($0.top, $0.line) < ($1.top, $1.line) }) {
            // A remote that follows a branch gets its role from it.
            guard roles[stretch.owner] == nil, localOfRemote[stretch.owner] == nil else { continue }
            // Nothing from a later page may decide this stretch's colour (§3.9): the window
            // searched around it stops at the end of the page it starts on. The stretch's
            // own bottom is not clipped to the page; the clamp on the window is what counts.
            let pageLast = input.pageEnd(containing: stretch.top) - 1
            let windowEnd = min(stretch.bottom + 2, pageLast)
            var taken = Array(repeating: false, count: paletteSize)
            for column in [stretch.column - 1, stretch.column + 1] {
                for next in neighbours.overlapping(column: column, from: stretch.top - 2, to: windowEnd) {
                    if case .pool(let index)? = roles[next.owner] {
                        taken[index] = true
                    }
                }
            }
            let index = leastUsed(usage, avoiding: taken)
            usage[index] += 1
            roles[stretch.owner] = .pool(index)
            for follower in followers[stretch.owner] ?? [] {
                roles[follower] = .pool(index)
            }
        }
        return GraphColoring(roleOfOwner: roles)
    }
}

// MARK: - Roles

private nonisolated extension GraphColoring {
    /// The role an owner has by what it is, or nil when it takes one from the palette.
    static func fixedRole(of owner: GraphOwner, headBranch: String?, input: GraphInput) -> GraphColorRole? {
        switch owner {
        case .head:
            return .head
        case .stash:
            return .stash
        case .branch(let name) where name == headBranch:
            return .head
        case .branch, .remote:
            switch input.rank(of: owner) {
            case 0?: return .main
            case 1?: return .develop
            default: return nil
            }
        case .unnamed:
            return nil
        }
    }

    /// For each remote owner in the graph, the local branch it follows: the one
    /// whose upstream it is, provided that branch has a role to give, which is
    /// a fixed one or a place in the graph to get one from the palette. With
    /// several branches on one remote, the lowest priority rank wins and then
    /// the name, so the order of the refs never matters. A remote trunk is
    /// never followed: its role comes from its own rank.
    static func remoteFollowers(_ input: GraphInput, owners: Set<GraphOwner>, headBranch: String?) -> [GraphOwner: GraphOwner] {
        var localOfRemote: [GraphOwner: GraphOwner] = [:]
        for ref in input.refs where ref.isLocalBranch {
            guard let upstream = ref.upstream, input.remoteTrunks[upstream] == nil else { continue }
            let remote = GraphOwner.remote(upstream)
            let local = GraphOwner.branch(ref.name)
            guard owners.contains(remote),
                  owners.contains(local) || fixedRole(of: local, headBranch: headBranch, input: input) != nil else { continue }
            if case .branch(let followed)? = localOfRemote[remote],
               (GraphPriority.rank(followed), followed) <= (GraphPriority.rank(ref.name), ref.name) {
                continue
            }
            localOfRemote[remote] = local
        }
        return localOfRemote
    }

    /// The index with the fewest owners among those not `taken`, the lowest on a
    /// tie; the same among all of them when every one is taken.
    static func leastUsed(_ usage: [Int], avoiding taken: [Bool]) -> Int {
        let free = usage.indices.filter { !taken[$0] }
        let candidates = free.isEmpty ? Array(usage.indices) : free
        return candidates.min { (usage[$0], $0) < (usage[$1], $1) } ?? 0
    }
}

// MARK: - Stretches

/// A piece of a drawn line, in its column, with one colour owner.
private nonisolated struct Stretch {
    let owner: GraphOwner
    let column: Int
    /// First and last row drawn, ends included.
    let top: Int
    let bottom: Int
    /// Index into `GraphLines.lines`.
    let line: Int
}

private nonisolated extension GraphColoring {
    /// The stretches of every drawn line.
    /// - A line other than HEAD's is one stretch, owned by the line's owner, from
    ///   its top to its bottom (clipped to the loaded rows when it runs past the end).
    /// - HEAD's line has one per group of consecutive rows with the same colour
    ///   owner. Each segment between two commits takes the colour of the one
    ///   above it, so a stretch runs on to the first row of the next one.
    static func makeStretches(_ input: GraphInput, lines: GraphLines, columns: GraphColumns, headOwner: GraphOwner) -> [Stretch] {
        let lastRow = input.commits.count - 1
        var stretches: [Stretch] = []
        for (index, line) in lines.lines.enumerated() {
            let column = columns.columnOfLine[index]
            guard line.owner == headOwner else {
                stretches.append(Stretch(owner: line.owner, column: column, top: line.top,
                                         bottom: min(line.bottom, lastRow), line: index))
                continue
            }
            var first = 0
            while first < line.rows.count {
                let owner = lines.colorOwnerOfRow[line.rows[first]]
                var next = first + 1
                while next < line.rows.count, lines.colorOwnerOfRow[line.rows[next]] == owner { next += 1 }
                stretches.append(Stretch(owner: owner, column: column,
                                         top: first == 0 ? line.top : line.rows[first],
                                         bottom: next < line.rows.count ? line.rows[next] : min(line.bottom, lastRow),
                                         line: index))
                first = next
            }
        }
        return stretches
    }
}

/// The stretches of each column sorted by first row. Two in a column never
/// overlap beyond a shared end row, so they are sorted by last row too and
/// finding the ones near a span is a binary search.
private nonisolated struct StretchesByColumn {
    private let byColumn: [Int: [Stretch]]

    init(_ stretches: [Stretch]) {
        byColumn = Dictionary(grouping: stretches, by: \.column).mapValues {
            $0.sorted { ($0.top, $0.bottom) < ($1.top, $1.bottom) }
        }
    }

    /// The stretches of `column` that share a row with `[low, high]`.
    func overlapping(column: Int, from low: Int, to high: Int) -> ArraySlice<Stretch> {
        guard let stretches = byColumn[column] else { return [] }
        var start = 0
        var end = stretches.count
        while start < end {
            let middle = start + (end - start) / 2
            if stretches[middle].bottom >= low { end = middle } else { start = middle + 1 }
        }
        var stop = start
        while stop < stretches.count, stretches[stop].top <= high { stop += 1 }
        return stretches[start..<stop]
    }
}
