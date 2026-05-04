import SwiftUI

struct CommitLogView: View {
    @Bindable var viewModel: RepositoryViewModel
    @State private var hoveredBranchId: Int?

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
                        ForEach(Array(viewModel.commits.enumerated()), id: \.element.id) { index, commit in
                            let layout = viewModel.graphLayouts.indices.contains(index) ? viewModel.graphLayouts[index] : nil
                            CommitRowView(
                                commit: commit,
                                isSelected: commit.id == viewModel.selectedCommitId,
                                refs: viewModel.refsBySha[commit.sha] ?? [],
                                graphRow: layout,
                                graphMaxLanes: viewModel.graphMaxLanes,
                                hoveredBranchId: hoveredBranchId,
                                onHoverChanged: { isHovering in
                                    hoveredBranchId = isHovering ? layout?.commitBranchId : nil
                                }
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
