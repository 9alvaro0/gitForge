import SwiftUI

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
        }
    }
}

private struct RepositoryContentView: View {
    let repository: Repository
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                CommitLogView(viewModel: viewModel)
                    .frame(minWidth: 320, idealWidth: 460)
                detailPane
                    .frame(minWidth: 320)
            }
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
            BranchFilterMenu(viewModel: viewModel)
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

private struct BranchFilterMenu: View {
    @Bindable var viewModel: RepositoryViewModel

    private var label: String {
        switch viewModel.selectedFilterBranch {
        case nil:
            return viewModel.currentBranchName ?? "HEAD"
        case "ALL":
            return "All branches"
        case .some(let name):
            return name
        }
    }

    var body: some View {
        Menu {
            Button {
                viewModel.selectedFilterBranch = nil
            } label: {
                if viewModel.selectedFilterBranch == nil {
                    Label("Current Branch", systemImage: "checkmark")
                } else {
                    Text("Current Branch")
                }
            }

            Button {
                viewModel.selectedFilterBranch = "ALL"
            } label: {
                if viewModel.selectedFilterBranch == "ALL" {
                    Label("All Branches", systemImage: "checkmark")
                } else {
                    Text("All Branches")
                }
            }

            if !viewModel.localBranches.isEmpty {
                Divider()
                Section("Local") {
                    ForEach(viewModel.localBranches) { ref in
                        Button {
                            viewModel.selectedFilterBranch = ref.name
                        } label: {
                            if viewModel.selectedFilterBranch == ref.name {
                                Label(ref.name, systemImage: "checkmark")
                            } else {
                                Text(ref.name)
                            }
                        }
                    }
                }
            }

            if !viewModel.remoteBranches.isEmpty {
                Section("Remote") {
                    ForEach(viewModel.remoteBranches) { ref in
                        Button {
                            viewModel.selectedFilterBranch = ref.name
                        } label: {
                            if viewModel.selectedFilterBranch == ref.name {
                                Label(ref.name, systemImage: "checkmark")
                            } else {
                                Text(ref.name)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 120, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

#Preview {
    RepositoryView(repository: Repository.preview)
        .environment(AppState.previewWithActive)
        .frame(width: 1100, height: 640)
}
