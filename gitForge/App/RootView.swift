import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.gitStatus {
            case .checking:
                ProgressView()
                    .controlSize(.large)
            case .available:
                ContentView()
            case .notFound:
                GitNotFoundView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
