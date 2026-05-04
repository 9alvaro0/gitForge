import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    @State private var showingCreateBranchSheet = false
    @State private var renameTarget: GitRef?
    @State private var deleteTarget: GitRef?
    @State private var dirtyCheckoutTarget: GitRef?
    @State private var unmergedDeleteTarget: GitRef?

    @AppStorage("sidebar.localBranchesExpanded") private var localExpanded = true
    @AppStorage("sidebar.remoteBranchesExpanded") private var remoteExpanded = true
    @AppStorage("sidebar.tagsExpanded") private var tagsExpanded = false
    @AppStorage("sidebar.stashesExpanded") private var stashesExpanded = true

    var body: some View {
        listContent
            .listStyle(.sidebar)
            .navigationTitle("gitForge")
            .toolbar { toolbarContent }
            .dropDestination(for: URL.self, action: handleDrop)
            .modifier(NewBranchSheetModifier(isPresented: $showingCreateBranchSheet, appState: appState))
            .modifier(RenameBranchSheetModifier(target: $renameTarget, appState: appState))
            .modifier(DeleteBranchAlertModifier(target: $deleteTarget, unmerged: $unmergedDeleteTarget, appState: appState))
            .modifier(ForceDeleteBranchAlertModifier(target: $unmergedDeleteTarget, appState: appState))
            .modifier(DirtyCheckoutAlertModifier(target: $dirtyCheckoutTarget, appState: appState))
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            Section("Repositories") {
                ForEach(appState.repositories) { repo in
                    SidebarRepositoryRow(repository: repo)
                }
            }
            if let viewModel = appState.activeViewModel {
                branchSections(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private func branchSections(viewModel: RepositoryViewModel) -> some View {
        let localTree = BranchTreeBuilder.build(from: viewModel.localBranches)
        let remoteTree = BranchTreeBuilder.build(from: viewModel.remoteBranches)
        let tagTree = BranchTreeBuilder.build(from: viewModel.tags)

        Section {
            if localExpanded {
                OutlineGroup(localTree, id: \.id, children: \.children) { node in
                    branchNodeView(node, viewModel: viewModel, canModify: true)
                }
            }
        } header: {
            CollapsibleSectionHeader(title: "Local Branches", isExpanded: $localExpanded) {
                Button {
                    showingCreateBranchSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("New Branch")
            }
        }

        if !viewModel.remoteBranches.isEmpty {
            Section {
                if remoteExpanded {
                    OutlineGroup(remoteTree, id: \.id, children: \.children) { node in
                        branchNodeView(node, viewModel: viewModel, canModify: false)
                    }
                }
            } header: {
                CollapsibleSectionHeader(title: "Remote Branches", isExpanded: $remoteExpanded)
            }
        }
        if !viewModel.tags.isEmpty {
            Section {
                if tagsExpanded {
                    OutlineGroup(tagTree, id: \.id, children: \.children) { node in
                        branchNodeView(node, viewModel: viewModel, canModify: false)
                    }
                }
            } header: {
                CollapsibleSectionHeader(title: "Tags", isExpanded: $tagsExpanded)
            }
        }
        if !viewModel.stashes.isEmpty {
            Section {
                if stashesExpanded {
                    ForEach(viewModel.stashes) { stash in
                        SidebarStashRow(stash: stash, viewModel: viewModel)
                    }
                }
            } header: {
                CollapsibleSectionHeader(title: "Stashes", isExpanded: $stashesExpanded)
            }
        }
    }

    @ViewBuilder
    private func branchNodeView(_ node: BranchTreeNode, viewModel: RepositoryViewModel, canModify: Bool) -> some View {
        switch node {
        case .folder(_, let name, _):
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(name).fontWeight(.medium)
                Spacer(minLength: 0)
            }
        case .ref(let leafName, let ref):
            SidebarBranchRow(
                ref: ref,
                leafName: leafName,
                viewModel: viewModel,
                onCheckout: { handleCheckout(ref, viewModel: viewModel) },
                onRename: canModify ? { renameTarget = ref } : nil,
                onDelete: canModify ? { deleteTarget = ref } : nil
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await appState.presentOpenRepositoryPanel() }
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("Open Repository (⌘O)")
        }
    }

    private func handleDrop(_ urls: [URL], _ point: CGPoint) -> Bool {
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

    private func handleCheckout(_ ref: GitRef, viewModel: RepositoryViewModel) {
        if !viewModel.status.isClean {
            dirtyCheckoutTarget = ref
            return
        }
        Task {
            let result = await viewModel.checkoutBranch(ref)
            if case .failure(let error) = result {
                appState.presentedError = PresentedError(error: error, title: "Couldn’t checkout")
            }
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
