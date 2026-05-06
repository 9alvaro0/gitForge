import SwiftUI

/// `.gf-detail` — right-side commit detail in the History view.
struct CommitDetailColumn: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    private var detail: CommitDetail? { viewModel.detailCache[commit.sha] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            shaLine
            Text(commit.subject)
                .font(AppFont.sans(14))
                .foregroundStyle(theme.palette.fg1)
            metaCard

            if let detail, !detail.bodyText.isEmpty {
                Text(detail.bodyText)
                    .font(AppFont.mono(12, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            filesSection

            actionsSection
        }
        .task(id: commit.sha) {
            _ = await viewModel.detail(for: commit)
        }
    }

    private var shaLine: some View {
        HStack(spacing: 8) {
            GFIcon(kind: .diamond, size: 14, stroke: theme.palette.fg1)
            Text(commit.shortSha)
                .font(AppFont.mono(13, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
            IconButton(.copy) {
                #if canImport(AppKit)
                NSPasteboard.general.declareTypes([.string], owner: nil)
                NSPasteboard.general.setString(commit.sha, forType: .string)
                #endif
            }
        }
    }

    private var metaCard: some View {
        HStack(spacing: 10) {
            Avatar(name: commit.authorName, size: 20, colorSeed: commit.authorEmail)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.authorName)
                    .font(AppFont.sans(12, weight: .medium))
                    .foregroundStyle(theme.palette.fg1)
                Text(commit.authorEmail)
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
            }
            Spacer()
            Text(relativeWhen)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg2))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }

    @ViewBuilder
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FILES CHANGED")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.fg3)
                Text("\(detail?.files.count ?? 0)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.palette.fg3)
            }
            if let detail {
                VStack(spacing: 1) {
                    ForEach(detail.files) { f in
                        FileMiniRow(file: f, isActive: viewModel.selectedCommitFile == f.path) {
                            viewModel.selectedCommitFile = f.path
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    @State private var newBranchSheet = false
    @State private var newBranchName: String = ""
    @State private var cherryPickConfirm = false
    @State private var revertConfirm = false
    @State private var resetMode: GitCLI.ResetMode?
    @State private var newTagSheet = false
    @State private var newTagName: String = ""
    @State private var newTagMessage: String = ""

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIONS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                GFButton(title: "Create branch") {
                    newBranchName = ""
                    newBranchSheet = true
                }
                GFButton(title: "Create tag") {
                    newTagName = ""
                    newTagMessage = ""
                    newTagSheet = true
                }
                GFButton(title: "Cherry-pick") { cherryPickConfirm = true }
                GFButton(title: "Revert") { revertConfirm = true }
                Menu {
                    ForEach(GitCLI.ResetMode.allCases) { mode in
                        Button(mode.label) { resetMode = mode }
                    }
                } label: {
                    Text("Reset to here")
                        .font(AppFont.sans(12))
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .foregroundStyle(theme.palette.fg1)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.lineStrong, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(height: 28)
            }
        }
        .sheet(isPresented: $newBranchSheet) { newBranchSheetView }
        .sheet(isPresented: $newTagSheet) { newTagSheetView }
        .confirmationDialog("Cherry-pick \(commit.shortSha)?",
                            isPresented: $cherryPickConfirm,
                            titleVisibility: .visible) {
            Button("Cherry-pick") {
                Task { await runCherryPick() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replays the changes from this commit on top of the current branch.")
        }
        .confirmationDialog("Revert \(commit.shortSha)?",
                            isPresented: $revertConfirm,
                            titleVisibility: .visible) {
            Button("Revert") {
                Task { await runRevert() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a new commit that undoes the changes from this commit.")
        }
        .confirmationDialog("Reset to \(commit.shortSha)?",
                            isPresented: resetConfirmBinding,
                            titleVisibility: .visible) {
            Button(resetMode == .hard ? "Reset (destructive)" : "Reset",
                   role: resetMode == .hard ? .destructive : nil) {
                if let mode = resetMode { Task { await runReset(mode: mode) } }
            }
            Button("Cancel", role: .cancel) { resetMode = nil }
        } message: {
            Text(resetMode?.label ?? "")
        }
    }

    private var resetConfirmBinding: Binding<Bool> {
        Binding(get: { resetMode != nil }, set: { if !$0 { resetMode = nil } })
    }

    private var newBranchSheetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New branch from \(commit.shortSha)").font(AppFont.sans(14, weight: .semibold))
            GFTextField(placeholder: "feat/awesome", text: $newBranchName)
            HStack {
                GFButton(title: "Cancel") { newBranchSheet = false }
                Spacer()
                GFButton(title: "Create & checkout", style: .primary, disabled: newBranchName.isEmpty) {
                    let name = newBranchName
                    let sha = commit.sha
                    Task {
                        _ = await viewModel.createBranch(name: name, startingAt: sha, checkout: true)
                        newBranchSheet = false
                    }
                }
            }
        }
        .padding(20).frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(appState.theme)
    }

    private var newTagSheetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New tag at \(commit.shortSha)").font(AppFont.sans(14, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(AppFont.sans(11, weight: .medium)).foregroundStyle(theme.palette.fg3)
                GFTextField(placeholder: "v1.2.3", text: $newTagName)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Message (optional — annotated tag if set)")
                    .font(AppFont.sans(11, weight: .medium)).foregroundStyle(theme.palette.fg3)
                GFTextField(placeholder: "Release 1.2.3", text: $newTagMessage)
            }
            HStack {
                GFButton(title: "Cancel") { newTagSheet = false }
                Spacer()
                GFButton(title: "Create tag", style: .primary, disabled: newTagName.isEmpty) {
                    Task { await runCreateTag() }
                }
            }
        }
        .padding(20).frame(width: 420)
        .background(theme.palette.bg1)
        .appTheme(appState.theme)
    }

    @MainActor
    private func runCreateTag() async {
        let name = newTagName
        let message = newTagMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await viewModel.createTag(
            name: name,
            at: commit.sha,
            message: message.isEmpty ? nil : message
        )
        switch result {
        case .success:
            appState.activeToast = ToastMessage(message: "Tagged \(commit.shortSha) as \(name)", kind: .ok)
            newTagSheet = false
        case .failure(let err):
            appState.activeToast = ToastMessage(
                message: (err as? LocalizedError)?.errorDescription ?? err.localizedDescription,
                kind: .error
            )
        }
    }

    private var relativeWhen: String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: commit.authorDate, relativeTo: .now)
    }

    @MainActor
    private func runCherryPick() async {
        let outcome = await viewModel.cherryPick(commit)
        report(outcome,
               success: "Cherry-picked \(commit.shortSha)",
               conflicts: "Cherry-pick has conflicts — resolve to continue")
    }

    @MainActor
    private func runRevert() async {
        let outcome = await viewModel.revert(commit)
        report(outcome,
               success: "Reverted \(commit.shortSha)",
               conflicts: "Revert has conflicts — resolve to continue")
    }

    @MainActor
    private func runReset(mode: GitCLI.ResetMode) async {
        let outcome = await viewModel.reset(to: commit.sha, mode: mode)
        report(outcome,
               success: "Reset \(mode.rawValue) to \(commit.shortSha)",
               conflicts: "Reset has conflicts — resolve to continue")
    }

    @MainActor
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
}

private struct FileMiniRow: View {
    let file: CommitFileChange
    let isActive: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                StatusTag(kind: tagKind)
                Text(file.path)
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(isActive ? theme.palette.bg3 : .clear))
        }
        .buttonStyle(.plain)
    }

    private var tagKind: StatusTag.Kind {
        switch file.status {
        case .added: return .added
        case .modified, .typeChanged: return .modified
        case .deleted: return .deleted
        case .renamed: return .renamed
        case .copied: return .copied
        case .unmerged: return .unmerged
        case .unknown: return .modified
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommitDetailColumn(commit: Commit.preview, viewModel: RepositoryViewModel.preview)
        .frame(width: DesignTokens.Detail.panelWidth, height: 720)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
