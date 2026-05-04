import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    @State private var showingCreateBranchSheet = false
    @State private var renameTarget: GitRef?
    @State private var deleteTarget: GitRef?
    @State private var dirtyCheckoutTarget: GitRef?
    @State private var unmergedDeleteTarget: GitRef?

    var body: some View {
        listContent
            .listStyle(.sidebar)
            .navigationTitle("gitForge")
            .toolbar { toolbarContent }
            .dropDestination(for: URL.self, action: handleDrop)
            .modifier(NewBranchSheetModifier(isPresented: $showingCreateBranchSheet, appState: appState))
            .modifier(RenameSheetModifier(target: $renameTarget, appState: appState))
            .modifier(DeleteAlertModifier(target: $deleteTarget, unmerged: $unmergedDeleteTarget, appState: appState))
            .modifier(UnmergedDeleteAlertModifier(target: $unmergedDeleteTarget, appState: appState))
            .modifier(DirtyCheckoutAlertModifier(target: $dirtyCheckoutTarget, appState: appState))
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            Section("Repositories") {
                ForEach(appState.repositories) { repo in
                    SidebarRow(repository: repo)
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
            OutlineGroup(localTree, id: \.id, children: \.children) { node in
                branchNodeView(node, viewModel: viewModel, canModify: true)
            }
        } header: {
            HStack {
                Text("Local Branches")
                Spacer()
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
            Section("Remote Branches") {
                OutlineGroup(remoteTree, id: \.id, children: \.children) { node in
                    branchNodeView(node, viewModel: viewModel, canModify: false)
                }
            }
        }
        if !viewModel.tags.isEmpty {
            Section("Tags") {
                OutlineGroup(tagTree, id: \.id, children: \.children) { node in
                    tagNodeView(node)
                }
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
            BranchRow(
                ref: ref,
                leafName: leafName,
                viewModel: viewModel,
                onCheckout: { handleCheckout(ref, viewModel: viewModel) },
                onRename: canModify ? { renameTarget = ref } : nil,
                onDelete: canModify ? { deleteTarget = ref } : nil
            )
        }
    }

    @ViewBuilder
    private func tagNodeView(_ node: BranchTreeNode) -> some View {
        switch node {
        case .folder(_, let name, _):
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(name).fontWeight(.medium)
                Spacer(minLength: 0)
            }
        case .ref(let leafName, _):
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                Text(leafName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
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

// MARK: - View modifiers

private struct NewBranchSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let appState: AppState

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            if let viewModel = appState.activeViewModel {
                NewBranchSheet(baseDescription: viewModel.currentBranchName ?? "HEAD") { name, shouldCheckout in
                    Task {
                        let result = await viewModel.createBranch(name: name, checkout: shouldCheckout)
                        if case .failure(let error) = result {
                            appState.presentedError = PresentedError(error: error, title: "Couldn’t create branch")
                        }
                    }
                }
            }
        }
    }
}

private struct RenameSheetModifier: ViewModifier {
    @Binding var target: GitRef?
    let appState: AppState

    func body(content: Content) -> some View {
        content.sheet(item: $target) { ref in
            if let viewModel = appState.activeViewModel {
                RenameBranchSheet(oldName: ref.name) { newName in
                    Task {
                        let result = await viewModel.renameBranch(from: ref.name, to: newName)
                        if case .failure(let error) = result {
                            appState.presentedError = PresentedError(error: error, title: "Couldn’t rename branch")
                        }
                    }
                }
            }
        }
    }
}

private struct DeleteAlertModifier: ViewModifier {
    @Binding var target: GitRef?
    @Binding var unmerged: GitRef?
    let appState: AppState

    private var isPresented: Binding<Bool> {
        Binding(
            get: { target != nil },
            set: { if !$0 { target = nil } }
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            "Delete branch \(target?.name ?? "")?",
            isPresented: isPresented,
            presenting: target
        ) { ref in
            Button("Delete", role: .destructive) {
                guard let viewModel = appState.activeViewModel else { return }
                Task {
                    let result = await viewModel.deleteBranch(ref, force: false)
                    if case .failure(let error) = result {
                        let stderr: String = {
                            if let gitError = error as? GitError,
                               case .commandFailed(_, _, let s) = gitError {
                                return s
                            }
                            return ""
                        }()
                        if stderr.contains("not fully merged") {
                            unmerged = ref
                        } else {
                            appState.presentedError = PresentedError(error: error, title: "Couldn’t delete branch")
                        }
                    }
                    target = nil
                }
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: { _ in
            Text("This removes the local branch reference. Commits remain in the repository.")
        }
    }
}

private struct UnmergedDeleteAlertModifier: ViewModifier {
    @Binding var target: GitRef?
    let appState: AppState

    private var isPresented: Binding<Bool> {
        Binding(
            get: { target != nil },
            set: { if !$0 { target = nil } }
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            "Branch \(target?.name ?? "") is not fully merged",
            isPresented: isPresented,
            presenting: target
        ) { ref in
            Button("Force Delete", role: .destructive) {
                guard let viewModel = appState.activeViewModel else { return }
                Task {
                    let result = await viewModel.deleteBranch(ref, force: true)
                    if case .failure(let error) = result {
                        appState.presentedError = PresentedError(error: error, title: "Couldn’t force-delete branch")
                    }
                    target = nil
                }
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: { _ in
            Text("Some commits exist only on this branch and will become unreachable. Force delete anyway?")
        }
    }
}

private struct DirtyCheckoutAlertModifier: ViewModifier {
    @Binding var target: GitRef?
    let appState: AppState

    private var isPresented: Binding<Bool> {
        Binding(
            get: { target != nil },
            set: { if !$0 { target = nil } }
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            "Working copy has uncommitted changes",
            isPresented: isPresented,
            presenting: target
        ) { ref in
            Button("Continue Checkout") {
                guard let viewModel = appState.activeViewModel else { return }
                Task {
                    let result = await viewModel.checkoutBranch(ref)
                    if case .failure(let error) = result {
                        appState.presentedError = PresentedError(error: error, title: "Couldn’t checkout")
                    }
                    target = nil
                }
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: { ref in
            Text("Switching to “\(ref.displayName)” may carry your local changes. Commit or discard them first if you want a clean switch.")
        }
    }
}

// MARK: - Rows

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
    let leafName: String
    @Bindable var viewModel: RepositoryViewModel
    let onCheckout: () -> Void
    let onRename: (() -> Void)?
    let onDelete: (() -> Void)?

    private var isCurrent: Bool {
        ref.isLocalBranch && viewModel.currentBranchName == ref.name
    }

    private var isFiltered: Bool {
        viewModel.selectedFilterBranch == ref.name
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ref.isRemoteBranch ? "arrow.triangle.branch" : "point.topleft.down.to.point.bottomright.curvepath")
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(leafName)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .background(isFiltered ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedFilterBranch = ref.name
        }
        .onTapGesture(count: 2) {
            if !isCurrent { onCheckout() }
        }
        .contextMenu {
            if !isCurrent {
                Button("Checkout", action: onCheckout)
            }
            if let onRename {
                Button("Rename...", action: onRename)
            }
            if let onDelete, !isCurrent {
                Divider()
                Button("Delete...", role: .destructive, action: onDelete)
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
