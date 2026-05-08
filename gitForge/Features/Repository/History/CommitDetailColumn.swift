import SwiftUI

/// `.gf-detail` — right-side commit detail in the History view.
struct CommitDetailColumn: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel
    /// Optional handler for the close icon at the panel top. When `nil` the
    /// button is hidden — used by History to collapse the panel.
    var onClose: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    private var detail: CommitDetail? { viewModel.detailCache[commit.sha] }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
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
        HStack(spacing: DesignTokens.Spacing.md) {
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
            .help("Copy full SHA")
            Spacer()
            if let onClose {
                IconButton(.x, action: onClose)
                    .help("Hide commit detail")
            }
        }
    }

    private var metaCard: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Avatar(name: commit.authorName, size: 20, colorSeed: commit.authorEmail)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
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
        .padding(DesignTokens.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg2))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    @ViewBuilder
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("FILES CHANGED")
                    .font(.system(size: FontSize.footnote, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.fg3)
                Text("\(detail?.files.count ?? 0)")
                    .font(.system(size: FontSize.footnote))
                    .foregroundStyle(theme.palette.fg3)
            }
            if let detail {
                LazyVStack(spacing: DesignTokens.Spacing.hairline) {
                    ForEach(detail.files) { f in
                        FileMiniRow(
                            file: f,
                            absoluteURL: viewModel.repository.url.appendingPathComponent(f.path),
                            isActive: viewModel.selectedCommitFile == f.path
                        ) {
                            viewModel.selectedCommitFile = f.path
                        }
                    }
                }
            } else {
                filesPlaceholder
            }
        }
    }

    private static let placeholderPaths = [
        "Sources/Features/Repository/RepositoryView.swift",
        "Sources/Core/Git/GitCLI.swift",
        "Sources/DesignSystem/Components/EmptyState.swift",
        "README.md",
    ]

    private var filesPlaceholder: some View {
        LazyVStack(spacing: DesignTokens.Spacing.hairline) {
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: DesignTokens.Spacing.md) {
                    StatusTag(kind: .modified)
                    Text(Self.placeholderPaths[index % Self.placeholderPaths.count])
                        .font(AppFont.mono(11.5, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg2)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
        }
        .skeleton(true)
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("ACTIONS")
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DesignTokens.Spacing.sm), GridItem(.flexible(), spacing: DesignTokens.Spacing.sm)], spacing: DesignTokens.Spacing.sm) {
                CommitActionButton(
                    icon: .branch,
                    title: "Branch",
                    tooltip: "Create a new branch starting at \(commit.shortSha)."
                ) {
                    newBranchName = ""
                    newBranchSheet = true
                }
                CommitActionButton(
                    icon: .square,
                    title: "Tag",
                    tooltip: "Create a tag pointing at \(commit.shortSha)."
                ) {
                    newTagName = ""
                    newTagMessage = ""
                    newTagSheet = true
                }
                CommitActionButton(
                    icon: .plus,
                    title: "Cherry-pick",
                    tooltip: "Replay this commit on top of the current branch."
                ) {
                    cherryPickConfirm = true
                }
                CommitActionButton(
                    icon: .arrowU,
                    title: "Revert",
                    tooltip: "Create a new commit that undoes the changes from \(commit.shortSha)."
                ) {
                    revertConfirm = true
                }
            }
            Menu {
                ForEach(GitCLI.ResetMode.allCases) { mode in
                    Button(mode.label) { resetMode = mode }
                }
            } label: {
                CommitActionButtonLabel(
                    icon: .warn,
                    title: "Reset to here",
                    destructive: true,
                    trailingChevron: true
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Move HEAD of the current branch to \(commit.shortSha). Soft / mixed / hard control how the working tree is affected — hard discards uncommitted changes.")
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
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
        .padding(DesignTokens.Spacing.huge).frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(appState.theme)
    }

    private var newTagSheetView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("New tag at \(commit.shortSha)").font(AppFont.sans(14, weight: .semibold))
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Name").font(AppFont.sans(11, weight: .medium)).foregroundStyle(theme.palette.fg3)
                GFTextField(placeholder: "v1.2.3", text: $newTagName)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
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
        .padding(DesignTokens.Spacing.huge).frame(width: 420)
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
    let absoluteURL: URL
    let isActive: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.md) {
                StatusTag(kind: tagKind)
                Text(file.path)
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(isActive ? theme.palette.bg3 : .clear))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.sm))
        }
        .buttonStyle(.plain)
        .contextMenu {
            // The file may have been deleted after the commit; the OS handles
            // missing-file fallout (Open just fails silently).
            Button("Open in editor") {
                NSWorkspace.shared.open(absoluteURL)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([absoluteURL])
            }
            Divider()
            Button("Copy path") { copyToPasteboard(file.path) }
            Button("Copy filename") { copyToPasteboard((file.path as NSString).lastPathComponent) }
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
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

private struct CommitActionButton: View {
    let icon: GFIconKind
    let title: String
    let tooltip: String
    var destructive: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            CommitActionButtonLabel(
                icon: icon,
                title: title,
                destructive: destructive,
                hovering: hovering
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tooltip)
    }
}

private struct CommitActionButtonLabel: View {
    let icon: GFIconKind
    let title: String
    var destructive: Bool = false
    var trailingChevron: Bool = false
    var hovering: Bool = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            GFIcon(kind: icon, size: 13, stroke: foreground)
            Text(title)
                .font(AppFont.sans(12))
                .foregroundStyle(foreground)
            Spacer(minLength: 0)
            if trailingChevron {
                GFIcon(kind: .chevD, size: 11, stroke: theme.palette.fg3)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(background))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(border, lineWidth: DesignTokens.Stroke.regular))
        .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
    }

    private var background: Color {
        if destructive { return theme.palette.delSoft }
        return hovering ? theme.palette.bg4 : theme.palette.bg3
    }
    private var foreground: Color {
        if destructive { return theme.palette.del }
        return hovering ? theme.palette.fg1 : theme.palette.fg2
    }
    private var border: Color {
        if destructive { return theme.palette.del.opacity(hovering ? 0.55 : 0.3) }
        return hovering ? theme.palette.lineStrong : theme.palette.line
    }
}

#if DEBUG
#Preview {
    @Previewable @State var theme = AppTheme()
    CommitDetailColumn(commit: Commit.preview, viewModel: RepositoryViewModel.preview)
        .frame(width: DesignTokens.Detail.panelWidth, height: 720)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
#endif
