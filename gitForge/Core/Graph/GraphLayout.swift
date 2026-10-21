import Foundation

/// The colour a line, a node or a step is drawn with. The view maps each role
/// to a theme colour; the engine only decides which role goes where.
nonisolated enum GraphColorRole: Sendable, Hashable {
    /// The user's accent: HEAD's line.
    case head
    /// The main trunk (`main`, `master`, `trunk`).
    case main
    /// The develop trunk (`develop`, `dev`).
    case develop
    case stash
    /// Nothing owns it, such as the track of a parent that is not loaded.
    case neutral
    /// Index into the palette for the current accent.
    case pool(Int)
}
