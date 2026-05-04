import SwiftUI

struct CommitLogView: View {
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingInitial && viewModel.commits.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.loadError, viewModel.commits.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.commits.isEmpty {
                Text("No commits to display")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $viewModel.selectedCommitId) {
                        ForEach(viewModel.commits) { commit in
                            CommitRowView(
                                commit: commit,
                                isSelected: commit.id == viewModel.selectedCommitId
                            )
                            .tag(commit.id)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded(currentItem: commit) }
                            }
                        }
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView().controlSize(.small)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: viewModel.selectedCommitId) { _, new in
                        guard let new else { return }
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
            }
        }
    }
}

#Preview("Loaded") {
    CommitLogView(viewModel: RepositoryViewModel.preview)
        .frame(width: 480, height: 540)
}

#Preview("Loading") {
    CommitLogView(viewModel: RepositoryViewModel(repository: Repository.preview))
        .frame(width: 480, height: 540)
}
