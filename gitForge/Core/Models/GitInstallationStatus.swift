import Foundation

/// Whether the `git` CLI is reachable. Drives the top-level UI gate in
/// `RootView` (loading spinner / install prompt / shell).
enum GitInstallationStatus: Sendable, Equatable {
    case checking
    case available
    case notFound
}
