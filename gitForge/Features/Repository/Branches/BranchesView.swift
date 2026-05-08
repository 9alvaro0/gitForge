import SwiftUI

/// `.gf-view-branches` — local + remote + tags listing, organised hierarchically
/// by folder (`feature/`, `release/`, …) so big repos don't drown the list.
struct BranchesView: View {
    @Bindable var viewModel: RepositoryViewModel

    @State private var filter: String = ""
    @State private var newBranchSheet = false
    @State private var newBranchName: String = ""
    @State private var renameTarget: GitRef?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: GitRef?
    @State private var deleteForce: Bool = false
    @State private var mergeRequest: MergeRequest?
    @State private var rebaseTarget: GitRef?
    @State private var deleteTargetTag: GitRef?

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    /// "Merge `source` into `target`" — `target == nil` means current branch.
    struct MergeRequest: Identifiable, Equatable {
        let id = UUID()
        let source: GitRef
        let target: GitRef?
    }

    private var localBranches: [GitRef]  { viewModel.localBranches.filter(matchesFilter) }
    private var remoteBranches: [GitRef] { viewModel.remoteBranches.filter(matchesFilter) }
    private var tags: [GitRef]           { viewModel.tags.filter(matchesFilter) }
    private var currentBranchName: String? { viewModel.currentBranchName }

    private func matchesFilter(_ ref: GitRef) -> Bool {
        filter.isEmpty || ref.name.localizedCaseInsensitiveContains(filter)
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ContentHeader(title: "Branches") {
                EmptyView()
            } right: {
                GFTextField(placeholder: "Filter branches…", text: $filter).frame(width: 220)
                ToolButton(.push, label: "Push tags", disabled: viewModel.tags.isEmpty) {
                    Task { await runPushAllTags() }
                }
                ToolButton(.plus, label: "New branch", primary: true) {
                    newBranchName = ""
                    newBranchSheet = true
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xhuge) {
                    BranchSection(
                        title: "Local",
                        refs: localBranches,
                        availableTargets: viewModel.localBranches,
                        currentBranchName: currentBranchName,
                        viewModel: viewModel,
                        onCheckout: handleCheckout,
                        onRename: { renameTarget = $0; renameDraft = $0.name },
                        onDelete: { deleteTarget = $0; deleteForce = false },
                        onMerge: { source, target in mergeRequest = MergeRequest(source: source, target: target) },
                        onRebase: { rebaseTarget = $0 }
                    )
                    BranchSection(
                        title: "Remote",
                        refs: remoteBranches,
                        availableTargets: viewModel.localBranches,
                        currentBranchName: nil,
                        viewModel: viewModel,
                        onCheckout: handleCheckout,
                        onRename: nil,
                        onDelete: nil,
                        onMerge: { source, target in mergeRequest = MergeRequest(source: source, target: target) },
                        onRebase: { rebaseTarget = $0 }
                    )
                    if !tags.isEmpty {
                        TagsSection(
                            tags: tags,
                            onPush:   { ref in Task { await runPushTag(ref) } },
                            onDelete: { ref in deleteTargetTag = ref }
                        )
                    }
                }
                .padding(DesignTokens.Spacing.xxxxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .sheet(isPresented: $newBranchSheet) { newBranchSheetView(presented: $newBranchSheet) }
        .sheet(item: $renameTarget) { ref in renameSheetView(ref: ref) }
        .confirmationDialog("Delete \(deleteTarget?.name ?? "")?",
                            isPresented: deleteAlertBinding,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let ref = deleteTarget {
                    Task { _ = await viewModel.deleteBranch(ref, force: deleteForce) }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This removes the local branch reference. Use force-delete if it has unmerged commits.")
        }
        .confirmationDialog(mergeDialogTitle,
                            isPresented: mergeAlertBinding,
                            titleVisibility: .visible) {
            Button("Merge") {
                if let req = mergeRequest { Task { await runMerge(request: req) } }
                mergeRequest = nil
            }
            Button("Cancel", role: .cancel) { mergeRequest = nil }
        } message: {
            Text(mergeDialogMessage)
        }
        .confirmationDialog("Rebase \(currentBranchName ?? "current") onto \(rebaseTarget?.displayName ?? "")?",
                            isPresented: rebaseAlertBinding,
                            titleVisibility: .visible) {
            Button("Rebase") {
                if let ref = rebaseTarget { Task { await runRebase(ref: ref) } }
                rebaseTarget = nil
            }
            Button("Cancel", role: .cancel) { rebaseTarget = nil }
        } message: {
            Text("Replays \(currentBranchName ?? "current") on top of \(rebaseTarget?.displayName ?? ""). You'll need a force push afterwards.")
        }
        .confirmationDialog("Delete tag \(deleteTargetTag?.name ?? "")?",
                            isPresented: deleteTagAlertBinding,
                            titleVisibility: .visible) {
            Button("Delete locally", role: .destructive) {
                if let ref = deleteTargetTag { Task { await runDeleteTag(ref, alsoOnRemote: false) } }
                deleteTargetTag = nil
            }
            Button("Delete locally + remote", role: .destructive) {
                if let ref = deleteTargetTag { Task { await runDeleteTag(ref, alsoOnRemote: true) } }
                deleteTargetTag = nil
            }
            Button("Cancel", role: .cancel) { deleteTargetTag = nil }
        } message: {
            Text("Local-only is reversible (re-tag the same sha). Removing from origin notifies anyone who already pulled it.")
        }
    }

    private var deleteTagAlertBinding: Binding<Bool> {
        Binding(get: { deleteTargetTag != nil }, set: { if !$0 { deleteTargetTag = nil } })
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }
    private var mergeAlertBinding: Binding<Bool> {
        Binding(get: { mergeRequest != nil }, set: { if !$0 { mergeRequest = nil } })
    }

    private var mergeDialogTitle: String {
        guard let req = mergeRequest else { return "" }
        let target = req.target?.displayName ?? currentBranchName ?? "current"
        return "Merge \(req.source.displayName) into \(target)?"
    }

    private var mergeDialogMessage: String {
        guard let req = mergeRequest else { return "" }
        let target = req.target?.displayName ?? currentBranchName ?? "current"
        if let t = req.target, t.name != currentBranchName {
            return "Will check out \(target) first, then merge \(req.source.displayName) into it. Conflicts route you to the Conflicts view."
        }
        return "Brings \(req.source.displayName) into \(target). Conflicts route you to the Conflicts view."
    }
    private var rebaseAlertBinding: Binding<Bool> {
        Binding(get: { rebaseTarget != nil }, set: { if !$0 { rebaseTarget = nil } })
    }

    private func handleCheckout(_ ref: GitRef) { Task { _ = await viewModel.checkoutBranch(ref) } }

    private func runMerge(request: MergeRequest) async {
        let outcome = await viewModel.mergeBranch(source: request.source, into: request.target)
        let targetLabel = request.target?.displayName ?? currentBranchName ?? "HEAD"
        report(outcome,
               success: "Merged \(request.source.displayName) into \(targetLabel)",
               conflicts: "Merge has conflicts — resolve to continue")
    }

    private func runRebase(ref: GitRef) async {
        let outcome = await viewModel.rebaseOnto(ref)
        report(outcome,
               success: "Rebased \(currentBranchName ?? "HEAD") onto \(ref.displayName)",
               conflicts: "Rebase has conflicts — resolve to continue")
    }

    private func report(_ outcome: RepositoryViewModel.IntegrationOutcome,
                        success: String,
                        conflicts: String) {
        switch outcome {
        case .clean:
            appState.activeToast = ToastMessage(message: success, kind: .ok)
        case .conflicts:
            appState.workspaceSection = .conflict
            appState.activeToast = ToastMessage(message: conflicts, kind: .warn)
        case .failed(let message):
            appState.activeToast = ToastMessage(message: message, kind: .error)
        }
    }

    // MARK: Tag handlers

    private func runPushTag(_ ref: GitRef) async {
        let result = await viewModel.pushTag(ref)
        switch result {
        case .success:
            appState.activeToast = ToastMessage(message: "Pushed \(ref.name)", kind: .ok)
        case .failure(let err):
            appState.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error)
        }
    }

    private func runPushAllTags() async {
        let result = await viewModel.pushAllTags()
        switch result {
        case .success:
            appState.activeToast = ToastMessage(message: "Pushed all tags", kind: .ok)
        case .failure(let err):
            appState.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error)
        }
    }

    private func runDeleteTag(_ ref: GitRef, alsoOnRemote: Bool) async {
        if alsoOnRemote {
            let remoteResult = await viewModel.pushDeleteTag(ref)
            if case .failure(let err) = remoteResult {
                appState.activeToast = ToastMessage(
                    message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                    kind: .error)
                return
            }
        }
        let localResult = await viewModel.deleteTag(ref)
        switch localResult {
        case .success:
            let suffix = alsoOnRemote ? " (local + remote)" : " (local)"
            appState.activeToast = ToastMessage(message: "Deleted \(ref.name)\(suffix)", kind: .ok)
        case .failure(let err):
            appState.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error)
        }
    }

    @ViewBuilder
    private func newBranchSheetView(presented: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("New branch").font(AppFont.sans(14, weight: .semibold))
            GFTextField(placeholder: "feat/awesome", text: $newBranchName)
            HStack {
                GFButton(title: "Cancel") { presented.wrappedValue = false }
                Spacer()
                GFButton(title: "Create & checkout", style: .primary, disabled: newBranchName.isEmpty) {
                    let target = newBranchName
                    Task {
                        _ = await viewModel.createBranch(name: target, checkout: true)
                        presented.wrappedValue = false
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.huge).frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(appState.theme)
    }

    @ViewBuilder
    private func renameSheetView(ref: GitRef) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("Rename \(ref.name)").font(AppFont.sans(14, weight: .semibold))
            GFTextField(placeholder: ref.name, text: $renameDraft)
            HStack {
                GFButton(title: "Cancel") { renameTarget = nil }
                Spacer()
                GFButton(title: "Rename", style: .primary, disabled: renameDraft.isEmpty || renameDraft == ref.name) {
                    let target = renameDraft
                    Task {
                        _ = await viewModel.renameBranch(from: ref.name, to: target)
                        renameTarget = nil
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.huge).frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(appState.theme)
    }
}

// MARK: - Section

private struct FlatRow: Identifiable {
    enum Kind {
        case folder(path: String, name: String, count: Int, collapsed: Bool)
        case leaf(ref: GitRef, leafName: String)
    }
    let id: String
    let depth: Int
    let kind: Kind
}

private struct BranchSection: View {
    let title: String
    let refs: [GitRef]
    /// Local branches that can be the destination of a merge.
    let availableTargets: [GitRef]
    let currentBranchName: String?
    let viewModel: RepositoryViewModel
    let onCheckout: (GitRef) -> Void
    let onRename: ((GitRef) -> Void)?
    let onDelete: ((GitRef) -> Void)?
    /// `(source, target)` — `target == nil` means current branch.
    let onMerge: ((GitRef, GitRef?) -> Void)?
    let onRebase: ((GitRef) -> Void)?

    @State private var collapsedFolders: Set<String> = []
    @Environment(\.appTheme) private var theme

    private var tree: [BranchTreeNode] { BranchTreeBuilder.build(from: refs) }

    /// Flatten the (possibly collapsed) tree into a single ordered list so the
    /// view body can be a flat `ForEach` instead of a recursive ViewBuilder.
    private var flatRows: [FlatRow] {
        var out: [FlatRow] = []
        func walk(_ nodes: [BranchTreeNode], depth: Int) {
            for node in nodes {
                switch node {
                case .ref(let leaf, let ref):
                    out.append(FlatRow(id: node.id, depth: depth,
                                       kind: .leaf(ref: ref, leafName: leaf)))
                case .folder(let path, let name, let children):
                    let collapsed = collapsedFolders.contains(path)
                    out.append(FlatRow(id: node.id, depth: depth,
                                       kind: .folder(path: path, name: name,
                                                      count: leafCount(in: children),
                                                      collapsed: collapsed)))
                    if !collapsed { walk(children, depth: depth + 1) }
                }
            }
        }
        walk(tree, depth: 0)
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(title.uppercased())
                    .font(.system(size: FontSize.footnote, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.fg3)
                Text("\(refs.count)")
                    .font(.system(size: FontSize.footnote))
                    .foregroundStyle(theme.palette.fg3)
            }
            .padding(.leading, DesignTokens.Spacing.xxs)
            if refs.isEmpty {
                Text("No branches.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.Spacing.xxl)
                    .padding(.vertical, DesignTokens.Spacing.xxl)
                    .background(card)
            } else {
                VStack(spacing: DesignTokens.Spacing.none) {
                    tableHeader
                    ForEach(flatRows) { row in
                        renderFlatRow(row)
                    }
                }
                .background(card)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            }
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .fill(theme.palette.bg3)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular)
            )
    }

    private var tableHeader: some View {
        HStack {
            Spacer().frame(width: DesignTokens.IconSize.md)
            Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
            Text("LAST COMMIT").frame(width: 200, alignment: .leading)
            Spacer().frame(width: 130)
        }
        .font(AppFont.mono(10.5, family: theme.monoFont))
        .tracking(0.6)
        .foregroundStyle(theme.palette.fg3)
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(theme.palette.bg4)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.lineStrong).frame(height: DesignTokens.Stroke.regular) }
    }

    @ViewBuilder
    private func renderFlatRow(_ row: FlatRow) -> some View {
        switch row.kind {
        case .leaf(let ref, let leafName):
            leafRow(ref: ref, leafName: leafName, depth: row.depth)
        case .folder(let path, let name, let count, _):
            folderRow(path: path, name: name, depth: row.depth, count: count)
        }
    }

    @ViewBuilder
    private func folderRow(path: String, name: String, depth: Int, count: Int) -> some View {
        let collapsed = collapsedFolders.contains(path)
        Button {
            if collapsed { collapsedFolders.remove(path) } else { collapsedFolders.insert(path) }
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Spacer().frame(width: CGFloat(depth) * 16 + 14)
                GFIcon(kind: collapsed ? .chevR : .chevD, size: 10, stroke: theme.palette.fg3)
                GFIcon(kind: .folder, size: 12, stroke: theme.palette.fg2)
                Text(name)
                    .font(AppFont.sans(12, weight: .medium))
                    .foregroundStyle(theme.palette.fg1)
                Text("\(count)")
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .contentShape(.rect)
            .background(.clear)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
    }

    @ViewBuilder
    private func leafRow(ref: GitRef, leafName: String, depth: Int) -> some View {
        let isCurrent = (ref.name == currentBranchName) && ref.isLocalBranch
        HStack(spacing: DesignTokens.Spacing.sm) {
            Spacer().frame(width: CGFloat(depth) * 16 + 14)
            if isCurrent {
                Circle().fill(theme.palette.accent).frame(width: DesignTokens.Spacing.sm, height: DesignTokens.Spacing.sm)
            } else {
                Color.clear.frame(width: DesignTokens.Spacing.sm, height: DesignTokens.Spacing.sm)
            }
            HStack(spacing: DesignTokens.Spacing.sm) {
                GFIcon(kind: ref.isRemoteBranch ? .cloud : .desktop, size: 12, stroke: theme.palette.fg2)
                Text(leafName)
                    .font(AppFont.mono(12, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                if isCurrent {
                    Pill(text: "HEAD", kind: .clean)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(lastCommitLabel(for: ref))
                .font(AppFont.mono(12, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: DesignTokens.Spacing.xs) {
                if !isCurrent {
                    GFButton(title: "Checkout", size: .small) { onCheckout(ref) }
                }
                OverflowMenu {
                    if !isCurrent { Button("Checkout") { onCheckout(ref) } }
                    if let onMerge {
                        Menu("Merge \(ref.displayName) into…") {
                            // Quick path for merging into the current branch.
                            if let current = currentBranchName, ref.name != current {
                                Button("\(current) (current)") { onMerge(ref, nil) }
                                Divider()
                            }
                            ForEach(otherTargets(excluding: ref)) { target in
                                Button(target.name) { onMerge(ref, target) }
                            }
                        }
                    }
                    if let onRebase, !isCurrent {
                        Button("Rebase \(currentBranchName ?? "current") onto this…") { onRebase(ref) }
                    }
                    if let onRename {
                        Divider()
                        Button("Rename…") { onRename(ref) }
                    }
                    if let onDelete, !isCurrent {
                        Divider()
                        Button("Delete…", role: .destructive) { onDelete(ref) }
                    }
                }
            }
            .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(isCurrent ? theme.palette.accent.opacity(DesignTokens.Opacity.faint) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
        .contentShape(.rect)
        .onTapGesture(count: 2) {
            guard !isCurrent else { return }
            onCheckout(ref)
        }
    }

    /// Local branches usable as a merge target, excluding `excluded` and the
    /// current branch (handled separately as the "quick" item).
    private func otherTargets(excluding excluded: GitRef) -> [GitRef] {
        availableTargets.filter { target in
            target.id != excluded.id && target.name != currentBranchName
        }
    }

    private func leafCount(in nodes: [BranchTreeNode]) -> Int {
        nodes.reduce(0) { acc, node in
            switch node {
            case .ref:                            return acc + 1
            case .folder(_, _, let children):     return acc + leafCount(in: children)
            }
        }
    }

    private func lastCommitLabel(for ref: GitRef) -> String {
        if let commit = viewModel.commits.first(where: { $0.sha == ref.targetSha }) {
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
            return f.localizedString(for: commit.authorDate, relativeTo: .now)
        }
        return String(ref.targetSha.prefix(7))
    }
}

// MARK: - Tags

private struct TagsSection: View {
    let tags: [GitRef]
    let onPush: (GitRef) -> Void
    let onDelete: (GitRef) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("TAGS")
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            FlowLayout(spacing: DesignTokens.Spacing.sm) {
                ForEach(tags) { tag in
                    Menu {
                        Button("Push to origin") { onPush(tag) }
                        Divider()
                        Button("Delete…", role: .destructive) { onDelete(tag) }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            GFIcon(kind: .tag, size: 10, stroke: theme.palette.mod)
                            Text(tag.name).font(AppFont.mono(11.5, family: theme.monoFont))
                        }
                        .foregroundStyle(theme.palette.mod)
                        .padding(.horizontal, DesignTokens.Spacing.lg).padding(.vertical, DesignTokens.Spacing.xs)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl).fill(theme.palette.mod.opacity(DesignTokens.Opacity.subtle)))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl).stroke(theme.palette.mod.opacity(DesignTokens.Opacity.strong), lineWidth: DesignTokens.Stroke.regular))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var theme = AppTheme()
    BranchesView(viewModel: RepositoryViewModel.preview)
        .environment(AppState.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
#endif
