import SwiftUI

/// `.gf-view-branches` — local + remote + tags listing, fully wired against
/// the active `RepositoryViewModel` (checkout / rename / delete / new branch).
struct BranchesView: View {
    @Bindable var viewModel: RepositoryViewModel

    @State private var filter: String = ""
    @State private var newBranchSheet = false
    @State private var newBranchName: String = ""
    @State private var renameTarget: GitRef?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: GitRef?
    @State private var deleteForce: Bool = false
    @State private var mergeTarget: GitRef?
    @State private var rebaseTarget: GitRef?

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    private var localBranches: [GitRef]  { viewModel.localBranches.filter(matchesFilter) }
    private var remoteBranches: [GitRef] { viewModel.remoteBranches.filter(matchesFilter) }
    private var tags: [GitRef]           { viewModel.tags.filter(matchesFilter) }
    private var currentBranchName: String? { viewModel.currentBranchName }

    private func matchesFilter(_ ref: GitRef) -> Bool {
        filter.isEmpty || ref.name.localizedCaseInsensitiveContains(filter)
    }

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Branches") {
                EmptyView()
            } right: {
                GFTextField(placeholder: "Filter branches…", text: $filter).frame(width: 220)
                ToolButton(.plus, label: "New branch", primary: true) {
                    newBranchName = ""
                    newBranchSheet = true
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    BranchSection(title: "Local",
                                  refs: localBranches,
                                  currentBranchName: currentBranchName,
                                  viewModel: viewModel,
                                  onCheckout: { ref in Task { _ = await viewModel.checkoutBranch(ref) } },
                                  onRename: { ref in renameTarget = ref; renameDraft = ref.name },
                                  onDelete: { ref in deleteTarget = ref; deleteForce = false },
                                  onMerge: { ref in mergeTarget = ref },
                                  onRebase: { ref in rebaseTarget = ref })
                    BranchSection(title: "Remote",
                                  refs: remoteBranches,
                                  currentBranchName: nil,
                                  viewModel: viewModel,
                                  onCheckout: { ref in Task { _ = await viewModel.checkoutBranch(ref) } },
                                  onRename: nil,
                                  onDelete: nil,
                                  onMerge: { ref in mergeTarget = ref },
                                  onRebase: { ref in rebaseTarget = ref })
                    if !tags.isEmpty {
                        TagsSection(tags: tags)
                    }
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .sheet(isPresented: $newBranchSheet) { newBranchSheet(presented: $newBranchSheet) }
        .sheet(item: $renameTarget) { ref in renameSheet(ref: ref) }
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
        .confirmationDialog("Merge \(mergeTarget?.displayName ?? "") into \(currentBranchName ?? "current")?",
                            isPresented: mergeAlertBinding,
                            titleVisibility: .visible) {
            Button("Merge") {
                if let ref = mergeTarget {
                    let target = ref
                    Task { await runMerge(ref: target) }
                }
                mergeTarget = nil
            }
            Button("Cancel", role: .cancel) { mergeTarget = nil }
        } message: {
            Text("Brings \(mergeTarget?.displayName ?? "") into the current branch. If conflicts arise you'll be sent to the Conflicts view.")
        }
        .confirmationDialog("Rebase \(currentBranchName ?? "current") onto \(rebaseTarget?.displayName ?? "")?",
                            isPresented: rebaseAlertBinding,
                            titleVisibility: .visible) {
            Button("Rebase") {
                if let ref = rebaseTarget {
                    let target = ref
                    Task { await runRebase(ref: target) }
                }
                rebaseTarget = nil
            }
            Button("Cancel", role: .cancel) { rebaseTarget = nil }
        } message: {
            Text("Replays \(currentBranchName ?? "current") on top of \(rebaseTarget?.displayName ?? ""). You'll need a force push afterwards.")
        }
    }

    private var mergeAlertBinding: Binding<Bool> {
        Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } })
    }

    private var rebaseAlertBinding: Binding<Bool> {
        Binding(get: { rebaseTarget != nil }, set: { if !$0 { rebaseTarget = nil } })
    }

    private func runMerge(ref: GitRef) async {
        let outcome = await viewModel.mergeBranch(ref)
        handleIntegration(outcome,
                          successLabel: "Merged \(ref.displayName) into \(currentBranchName ?? "HEAD")",
                          conflictLabel: "Merge has conflicts — resolve to continue")
    }

    private func runRebase(ref: GitRef) async {
        let outcome = await viewModel.rebaseOnto(ref)
        handleIntegration(outcome,
                          successLabel: "Rebased \(currentBranchName ?? "HEAD") onto \(ref.displayName)",
                          conflictLabel: "Rebase has conflicts — resolve to continue")
    }

    private func handleIntegration(_ outcome: RepositoryViewModel.IntegrationOutcome,
                                   successLabel: String,
                                   conflictLabel: String) {
        switch outcome {
        case .clean:
            appState.activeToast = ToastMessage(message: successLabel, kind: .ok)
        case .conflicts:
            appState.workspaceSection = .conflict
            appState.activeToast = ToastMessage(message: conflictLabel, kind: .warn)
        case .failed(let message):
            appState.activeToast = ToastMessage(message: message, kind: .error)
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    @ViewBuilder
    private func newBranchSheet(presented: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(20).frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(viewModel.previewTheme())
    }

    @ViewBuilder
    private func renameSheet(ref: GitRef) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(20).frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(viewModel.previewTheme())
    }
}

private struct BranchSection: View {
    let title: String
    let refs: [GitRef]
    let currentBranchName: String?
    let viewModel: RepositoryViewModel
    let onCheckout: (GitRef) -> Void
    let onRename: ((GitRef) -> Void)?
    let onDelete: ((GitRef) -> Void)?
    let onMerge: ((GitRef) -> Void)?
    let onRebase: ((GitRef) -> Void)?

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.fg3)
                Text("\(refs.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.palette.fg3)
            }
            if refs.isEmpty {
                Text("No branches.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
            } else {
                tableHeader
                ForEach(refs) { ref in
                    row(for: ref)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: 1))
    }

    private var tableHeader: some View {
        HStack {
            Spacer().frame(width: 14)
            Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
            Text("LAST COMMIT").frame(width: 200, alignment: .leading)
            Spacer().frame(width: 130)
        }
        .font(AppFont.mono(10.5, family: theme.monoFont))
        .tracking(0.6)
        .foregroundStyle(theme.palette.fg3)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }

    @ViewBuilder
    private func row(for ref: GitRef) -> some View {
        let isCurrent = (ref.name == currentBranchName) && ref.isLocalBranch
        HStack(spacing: 6) {
            if isCurrent {
                Circle().fill(theme.palette.accent).frame(width: 6, height: 6)
            } else {
                Color.clear.frame(width: 6, height: 6)
            }
            HStack(spacing: 6) {
                GFIcon(kind: .branch, size: 12, stroke: theme.palette.fg2)
                Text(ref.displayName)
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
            HStack(spacing: 4) {
                if !isCurrent && ref.isLocalBranch {
                    GFButton(title: "Checkout", size: .small) { onCheckout(ref) }
                } else if ref.isRemoteBranch {
                    GFButton(title: "Checkout", size: .small) { onCheckout(ref) }
                }
                OverflowMenu {
                    if !isCurrent { Button("Checkout") { onCheckout(ref) } }
                    if let onMerge, !isCurrent {
                        Button("Merge into \(currentBranchName ?? "current")…") { onMerge(ref) }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isCurrent ? theme.palette.accent.opacity(0.06) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }

    private func lastCommitLabel(for ref: GitRef) -> String {
        if let commit = viewModel.commits.first(where: { $0.sha == ref.targetSha }) {
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
            return f.localizedString(for: commit.authorDate, relativeTo: .now)
        }
        return String(ref.targetSha.prefix(7))
    }
}

private struct TagsSection: View {
    let tags: [GitRef]
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TAGS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            FlowLayout(spacing: 6) {
                ForEach(tags) { tag in
                    HStack(spacing: 5) {
                        GFIcon(kind: .diamond, size: 10, stroke: theme.palette.mod)
                        Text(tag.name).font(AppFont.mono(11.5, family: theme.monoFont))
                    }
                    .foregroundStyle(theme.palette.mod)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.palette.mod.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.palette.mod.opacity(0.25), lineWidth: 1))
                }
            }
        }
    }
}

/// Tiny helper so sheets can share the same theme without re-reading the env.
private extension RepositoryViewModel {
    @MainActor
    func previewTheme() -> AppTheme { AppTheme() }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    BranchesView(viewModel: RepositoryViewModel.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
