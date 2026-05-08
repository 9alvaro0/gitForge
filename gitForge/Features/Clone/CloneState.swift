import Foundation

/// Live state of the clone operation. Drives the progress bar and the
/// "Clone vs Cancel" button label in `CloneView`.
enum CloneState: Sendable, Equatable {
    case idle
    case running(stage: String, percent: Double)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
