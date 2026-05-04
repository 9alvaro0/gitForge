import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Repositories") {
                ForEach(appState.repositories) { repo in
                    SidebarRow(repository: repo)
                }
            }

            if let viewModel = appState.activeViewModel {
                if !viewModel.localBranches.isEmpty {
                    Section("Local Branches") {
                        ForEach(viewModel.localBranches) { ref in
                            BranchRow(ref: ref, viewModel: viewModel)
                        }
                    }
                }
                if !viewModel.remoteBranches.isEmpty {
                    Section("Remote Branches") {
                        ForEach(viewModel.remoteBranches) { ref in
                            BranchRow(ref: ref, viewModel: viewModel)
                        }
                    }
                }
                if !viewModel.tags.isEmpty {
                    Section("Tags") {
                        ForEach(viewModel.tags) { ref in
                            TagRow(ref: ref)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("gitForge")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await appState.presentOpenRepositoryPanel() }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Open Repository (⌘O)")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task {
                do {
                    try await appState.openRepository(at: url)
                } catch {
                    appState.presentedError = PresentedError(error: error)
                }
            }
            return true
        }
    }
}

private struct SidebarRow: View {
    let repository: Repository
    @Environment(AppState.self) private var appState

    private var isActive: Bool {
        appState.activeRepository?.url == repository.url
    }

    var body: some View {
        Button {
            Task { await appState.activate(repository) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "folder.fill" : "folder")
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(repository.name)
                        .fontWeight(isActive ? .semibold : .regular)
                    Text(repository.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from Recents", role: .destructive) {
                Task { await appState.removeFromRecents(repository.url) }
            }
        }
    }
}

private struct BranchRow: View {
    let ref: GitRef
    @Bindable var viewModel: RepositoryViewModel

    private var isCurrent: Bool {
        ref.isLocalBranch && viewModel.currentBranchName == ref.name
    }

    private var isFiltered: Bool {
        viewModel.selectedFilterBranch == ref.name
    }

    var body: some View {
        Button {
            viewModel.selectedFilterBranch = ref.name
        } label: {
            HStack(spacing: 8) {
                Image(systemName: ref.isRemoteBranch ? "arrow.triangle.branch" : "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(ref.displayName)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 1)
            .background(isFiltered ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

private struct TagRow: View {
    let ref: GitRef

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .foregroundStyle(.secondary)
            Text(ref.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

#Preview("With recents and branches") {
    NavigationSplitView {
        SidebarView()
            .environment(AppState.previewWithActive)
            .frame(minWidth: 260)
    } detail: {
        Color.clear
    }
    .frame(width: 720, height: 560)
}

#Preview("Empty") {
    NavigationSplitView {
        SidebarView()
            .environment(AppState())
            .frame(minWidth: 260)
    } detail: {
        Color.clear
    }
    .frame(width: 720, height: 560)
}
