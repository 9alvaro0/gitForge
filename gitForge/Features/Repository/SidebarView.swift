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
                        StashRow(stash: stash, viewModel: viewModel)
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

    private var iconName: String {
        switch ref.kind {
        case .localBranch: "point.topleft.down.to.point.bottomright.curvepath"
        case .remoteBranch: "arrow.triangle.branch"
        case .tag: "tag"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
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
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await viewModel.revealCommit(sha: ref.targetSha) }
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

private struct CollapsibleSectionHeader<Trailing: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, isExpanded: Binding<Bool>, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self._isExpanded = isExpanded
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            trailing()
        }
    }
}

private struct StashRow: View {
    let stash: Stash
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(stash.subject)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(stash.reference)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await viewModel.revealCommit(sha: stash.sha) }
        }
        .contextMenu {
            Button("Apply") {
                Task { await viewModel.applyStash(stash, drop: false) }
            }
            Button("Pop (apply and drop)") {
                Task { await viewModel.applyStash(stash, drop: true) }
            }
            Divider()
            Button("Drop", role: .destructive) {
                Task { await viewModel.dropStash(stash) }
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
