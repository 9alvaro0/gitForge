import Foundation

/// Lightweight per-repo status used by the sidebar so every row reflects the
/// real working-copy state, not just the active one. Refreshed periodically
/// from `AppState`; what's tracked is exactly what the row pills surface.
nonisolated struct RepoStatusSnapshot: Sendable, Equatable {
    var branch: String?
    var dirty: Int
    var ahead: Int
    var behind: Int
    /// `false` while the snapshot has never been computed for this repo —
    /// distinguishes "not loaded yet" from "loaded and clean", so the sidebar
    /// can show a placeholder pill instead of falsely flashing "clean".
    var loaded: Bool = true

    static let empty = RepoStatusSnapshot(branch: nil, dirty: 0, ahead: 0, behind: 0, loaded: false)
}
