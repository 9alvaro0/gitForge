import SwiftUI

struct RepositoryView: View {
    let repository: Repository

    var body: some View {
        RepositoryContentView(repository: repository)
            .id(repository.url)
    }
}

private struct RepositoryContentView: View {
    let repository: Repository
    @State private var viewModel: RepositoryViewModel

    init(repository: Repository) {
        self.repository = repository
        self._viewModel = State(initialValue: RepositoryViewModel(repository: repository))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                CommitLogView(viewModel: viewModel)
                    .frame(minWidth: 320, idealWidth: 420)
                detailPane
                    .frame(minWidth: 320)
            }
        }
        .task {
            await viewModel.loadInitial()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .font(.title3.weight(.semibold))
                Text(repository.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
        }
        .padding()
        .background(.bar)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let commit = viewModel.selectedCommit {
            CommitDetailView(commit: commit, viewModel: viewModel)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.righthalf.inset.filled.arrow.right")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Select a commit to see its details")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    RepositoryView(repository: Repository.preview)
        .environment(AppState.previewWithActive)
        .frame(width: 1000, height: 640)
}
