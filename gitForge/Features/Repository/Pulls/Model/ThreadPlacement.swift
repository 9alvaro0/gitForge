import Foundation

/// Where each review thread shows in the Files tab.
nonisolated struct PlacedThreads: Equatable, Sendable {
    /// Under a line: file path → the line → its threads.
    var inline: [String: [DiffLineRef: [ReviewThread]]] = [:]
    /// Above a file's diff: outdated, not found in the diff, or on a file
    /// without a patch.
    var fileLevel: [String: [ReviewThread]] = [:]
    /// On files the PR no longer lists ("Other comments").
    var other: [ReviewThread] = []

    static let empty = PlacedThreads()

    /// Unresolved threads of `path`, outdated ones included.
    func openCount(for path: String) -> Int {
        let underLines = inline[path].map { Array($0.values.joined()) } ?? []
        return underLines.count { !$0.isResolved } + (fileLevel[path]?.count { !$0.isResolved } ?? 0)
    }

    var otherOpenCount: Int { other.count { !$0.isResolved } }
}

/// The lines each file's patch has, parsed once per patch: the threads
/// are placed again with every change to them (a resolve, a reload), and
/// the patch usually hasn't changed.
nonisolated struct DiffLineIndex {
    private let parse: @Sendable (String) -> [DiffHunk]
    private var byPath: [String: (patch: String, refs: Set<DiffLineRef>)] = [:]

    init(parse: @escaping @Sendable (String) -> [DiffHunk] = { DiffParser.parse($0) }) {
        self.parse = parse
    }

    mutating func refs(path: String, patch: String) -> Set<DiffLineRef> {
        if let known = byPath[path], known.patch == patch { return known.refs }
        let refs = Set(parse(patch).flatMap(\.lines).flatMap(DiffLineRef.refs(for:)))
        byPath[path] = (patch, refs)
        return refs
    }
}

/// Spreads threads over the PR's files (spec §4.3).
nonisolated enum ThreadPlacement {
    static func place(_ threads: [ReviewThread], in files: [PullRequestFileChange]) -> PlacedThreads {
        var index = DiffLineIndex()
        return place(threads, in: files, index: &index)
    }

    static func place(_ threads: [ReviewThread], in files: [PullRequestFileChange],
                      index: inout DiffLineIndex) -> PlacedThreads {
        var placed = PlacedThreads()
        // Each patch parsed once, however many threads it carries.
        var lineRefs: [String: Set<DiffLineRef>] = [:]
        for thread in threads {
            guard let file = files.first(where: { $0.path == thread.path })
                    ?? files.first(where: { $0.oldPath == thread.path }) else {
                placed.other.append(thread)
                continue
            }
            guard let patch = file.patch, !patch.isEmpty, !thread.isOutdated, let ref = thread.ref else {
                placed.fileLevel[file.path, default: []].append(thread)
                continue
            }
            let refs = lineRefs[file.path] ?? {
                let all = index.refs(path: file.path, patch: patch)
                lineRefs[file.path] = all
                return all
            }()
            if refs.contains(ref) {
                placed.inline[file.path, default: [:]][ref, default: []].append(thread)
            } else {
                placed.fileLevel[file.path, default: []].append(thread)
            }
        }
        return placed
    }
}
