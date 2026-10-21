import Foundation

/// Which side of a diff a line number counts on: the old file or the new.
nonisolated enum DiffSide: Hashable, Sendable {
    case old, new
}

/// A line of a diff as the hosts address it: a side and a number there.
nonisolated struct DiffLineRef: Hashable, Sendable {
    let side: DiffSide
    let line: Int

    /// Every way a host can point at `line`. A context line exists on both
    /// sides, so a GitHub comment left on its `LEFT` still finds it.
    static func refs(for line: DiffLine) -> [DiffLineRef] {
        switch line.kind {
        case .removed:
            line.oldLineNumber.map { [DiffLineRef(side: .old, line: $0)] } ?? []
        case .added:
            line.newLineNumber.map { [DiffLineRef(side: .new, line: $0)] } ?? []
        case .context:
            [line.newLineNumber.map { DiffLineRef(side: .new, line: $0) },
             line.oldLineNumber.map { DiffLineRef(side: .old, line: $0) }].compactMap { $0 }
        case .noNewline:
            []
        }
    }

    /// Where a new comment on `line` goes in the unified view: a removed
    /// line on the old side, anything else on the new; `nil` where the
    /// hosts take no comment.
    static func commentSide(for line: DiffLine) -> DiffSide? {
        switch line.kind {
        case .removed: .old
        case .added, .context: .new
        case .noNewline: nil
        }
    }
}
