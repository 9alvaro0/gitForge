import SwiftUI

enum RepositoryTab: String, CaseIterable, Identifiable {
    case history
    case changes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "History"
        case .changes: "Changes"
        }
    }

    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .changes: "pencil.line"
        }
    }
}

struct RepositoryView: View {
    let repository: Repository
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let viewModel = appState.activeViewModel,
               viewModel.repository.url == repository.url {
                RepositoryContentView(repository: repository, viewModel: viewModel)
                    .id(repository.url)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: repository.url) {
            guard let viewModel = appState.activeViewModel else { return }
            await viewModel.loadInitial()
            await viewModel.loadRefs()
            await viewModel.refreshStatus()
        }
    }
}

#Preview {
    RepositoryView(repository: Repository.preview)
        .environment(AppState.previewWithActive)
        .frame(width: 1280, height: 680)
}
