import SwiftUI

/// `.gf-view-staging` — Changes view: file list + commit composer + diff pane.
struct StagingView: View {
    @Bindable var viewModel: RepositoryViewModel

    @Environment(\.appTheme) private var theme
    @State private var commitMessage: String = ""
    @State private var commitDescription: String = ""
    @State private var diffMode: DiffPane.ViewMode = .unified

    private var staged: [WorkingCopyFile]   { viewModel.status.stagedFiles }
    private var unstaged: [WorkingCopyFile] { viewModel.status.unstagedFiles }

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Changes") {
                MonoText("\(staged.count) staged · \(unstaged.count) unstaged", dim: true)
            } right: {
                ToolButton(.stash, label: "Stash") { Task { _ = await viewModel.stashAll() } }
                ToolButton(.x, label: "Discard all") {
                    Task { await viewModel.discardChanges(viewModel.status.files) }
                }
            }
            HStack(spacing: 0) {
                filesColumn
                diffColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    private var filesColumn: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                fileSectionHeader(title: "Staged", count: staged.count, action: "Unstage all") {
                    Task { await viewModel.unstage(staged) }
                }
                if staged.isEmpty {
                    Text("Nothing staged")
                        .font(AppFont.sans(12))
                        .foregroundStyle(theme.palette.fg3)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                } else {
                    ForEach(staged) { f in
                        StagingRow(file: f, viewModel: viewModel)
                    }
                }
            }
            Divider().background(theme.palette.line)
            ScrollView {
                VStack(spacing: 0) {
                    fileSectionHeader(title: "Unstaged", count: unstaged.count, action: "Stage all") {
                        Task { await viewModel.stage(unstaged) }
                    }
                    ForEach(unstaged) { f in
                        StagingRow(file: f, viewModel: viewModel)
                    }
                }
            }
            commitBox
        }
        .frame(width: DesignTokens.Staging.filesWidth)
        .background(theme.palette.bg1)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.palette.lineStrong).frame(width: 1) }
    }

    @ViewBuilder
    private func fileSectionHeader(title: String, count: Int, action: String, onAction: @escaping () -> Void) -> some View {
        HStack {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .tracking(0.6)
                Text("(\(count))")
                    .font(AppFont.mono(10.5, family: theme.monoFont))
            }
            .foregroundStyle(theme.palette.fg3)
            Spacer()
            Button(action: onAction) {
                Text(action)
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.clear))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var diffColumn: some View {
        Group {
            if let file = viewModel.selectedWorkingCopyFile {
                DiffPane(
                    file: file.path,
                    hunks: viewModel.workingCopyDiff,
                    loading: viewModel.loadingWorkingCopyDiff,
                    hunkAction: file.isStaged ? .unstage : .stage,
                    onHunkAction: { hunkId in
                        Task {
                            if file.isStaged { await viewModel.unstageHunks(ids: [hunkId]) }
                            else             { await viewModel.stageHunks(ids: [hunkId]) }
                        }
                    },
                    viewMode: $diffMode
                )
            } else if !staged.isEmpty || !unstaged.isEmpty {
                EmptyState(icon: .diff, title: "Pick a file to see the diff",
                           subtitle: "Selection drives the right-hand pane.") { EmptyView() }
            } else {
                EmptyState(icon: .check, title: "Working tree is clean",
                           subtitle: "No changes to stage.") { EmptyView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var commitBox: some View {
        VStack(spacing: 8) {
            TextField("Commit message", text: $commitMessage)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.palette.bg3))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.palette.lineStrong, lineWidth: 1))
                .font(AppFont.sans(12.5))

            TextField("Description (optional)", text: $commitDescription, axis: .vertical)
                .lineLimit(3...3)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.palette.bg3))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.palette.lineStrong, lineWidth: 1))
                .font(AppFont.mono(12, family: theme.monoFont))

            HStack {
                MonoText("on \(viewModel.currentBranchName ?? "HEAD") · \(staged.count) files", dim: true)
                Spacer()
                GFButton(title: "Commit & push") { Task { await commit(push: true) } }
                GFButton(title: "Commit", style: .primary,
                         disabled: commitMessage.isEmpty || staged.isEmpty) {
                    Task { await commit(push: false) }
                }
            }

            Button {
                if commitMessage.isEmpty { commitMessage = "feat: " }
            } label: {
                HStack(spacing: 6) {
                    GFIcon(kind: .cmd, size: 12, stroke: theme.palette.fg3)
                    Text("Suggest commit message").font(AppFont.sans(11))
                }
                .foregroundStyle(theme.palette.fg3)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(theme.palette.lineStrong))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(theme.palette.bg2)
        .overlay(alignment: .top) { Rectangle().fill(theme.palette.lineStrong).frame(height: 1) }
    }

    private func commit(push: Bool) async {
        viewModel.commitSubject = commitMessage
        viewModel.commitBody = commitDescription
        let ok = await viewModel.commit()
        if ok, push { await viewModel.push() }
        if ok { commitMessage = ""; commitDescription = "" }
    }
}

private struct StagingRow: View {
    let file: WorkingCopyFile
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        let isSelected = viewModel.selectedWorkingCopyFile?.id == file.id
        Button(action: { viewModel.selectedWorkingCopyFile = file }) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { file.isStaged },
                    set: { _ in Task {
                        if file.isStaged { await viewModel.unstage([file]) }
                        else             { await viewModel.stage([file]) }
                    } }
                ))
                .toggleStyle(GFCheckboxStyle())
                StatusTag(kind: StatusTag.Kind(workingFile: file.isStaged ? file.stagedStatus : file.unstagedStatus))
                pathView
                Spacer()
                stats
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(height: 26)
            .background(isSelected ? theme.palette.bg4 : (hovering ? theme.palette.bg3 : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var pathView: some View {
        let parts = file.path.split(separator: "/")
        let directory = parts.dropLast().joined(separator: "/")
        let name = parts.last.map(String.init) ?? file.path
        return HStack(spacing: 0) {
            if !directory.isEmpty {
                Text("\(directory)/")
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(name)
                .font(AppFont.mono(11.5, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var stats: some View {
        EmptyView()
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    StagingView(viewModel: RepositoryViewModel.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

/// Square checkbox styled like the design `.gf-file-row input[type=checkbox]`.
struct GFCheckboxStyle: ToggleStyle {
    @Environment(\.appTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isOn ? theme.palette.accent : theme.palette.bg2)
                RoundedRectangle(cornerRadius: 3)
                    .stroke(configuration.isOn ? theme.palette.accent : theme.palette.lineStrong, lineWidth: 1)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
    }
}
