import Foundation

/// Payload for the global alert hosted in `RootView`. `AppState` exposes a
/// single `presentedError: PresentedError?` so any feature can surface a
/// user-facing failure without owning its own alert plumbing.
struct PresentedError: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String = "Couldn’t open repository", message: String) {
        self.title = title
        self.message = message
    }

    init(error: Error, title: String = "Couldn’t open repository") {
        self.title = title
        self.message = error.userMessage
    }
}
