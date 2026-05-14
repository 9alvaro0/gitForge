import SwiftUI
import AppKit

struct StagingRow: View {
    let file: WorkingCopyFile
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    /// Drives a per-row confirmation when the user picks "Discard changes"
    /// or "Delete file" on an untracked entry. Always confirms — there's no
    /// undo for this and the all-files variant already gates behind a dialog.
    @State private var pendingDiscard = false

    var body: some View {
        let isSelected = viewModel.selectedWorkingCopyFile?.id == file.id
        Button(action: { viewModel.selectedWorkingCopyFile = file }) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Toggle("", isOn: Binding(
                    get: { file.isStaged },
                    set: { _ in Task { await toggleStaged() } }
                ))
                .toggleStyle(GFCheckboxStyle())
                .accessibilityLabel("\(file.isStaged ? "Unstage" : "Stage") \(file.path)")
                .accessibilityValue(statusDescription)
                StatusTag(kind: StatusTag.Kind(workingFile: file.isStaged ? file.stagedStatus : file.unstagedStatus))
                pathView
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(height: DesignTokens.IconSize.huge)
            .background(isSelected ? theme.palette.bg4 : (hovering ? theme.palette.bg3 : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(statusDescription): \(file.path)")
        .onHover { hovering = $0 }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { Task { await toggleStaged() } }
        )
        .help(file.isStaged ? "Double-click to unstage" : "Double-click to stage")
        .contextMenu { contextMenu }
        .confirmationDialog(
            file.isUntracked ? "Delete \(filename)?" : "Discard changes to \(filename)?",
            isPresented: $pendingDiscard,
            titleVisibility: .visible
        ) {
            Button(file.isUntracked ? "Delete file" : "Discard changes",
                   role: .destructive) {
                Task { await viewModel.discardChanges([file]) }
            }
        } message: {
            Text(file.isUntracked
                 ? "The file will be removed from disk. This can't be undone from the app."
                 : "Local changes will be reverted to the last committed version. This can't be undone.")
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if file.isStaged {
            Button("Unstage") { Task { await viewModel.unstage([file]) } }
        } else {
            Button("Stage") { Task { await viewModel.stage([file]) } }
        }
        if file.isUntracked {
            Button("Delete file", role: .destructive) {
                pendingDiscard = true
            }
        } else {
            Button(file.isUnmerged ? "Discard conflict (revert to HEAD)" : "Discard changes",
                   role: .destructive) {
                pendingDiscard = true
            }
        }
        Divider()
        Button("Open in editor") {
            NSWorkspace.shared.open(absoluteURL)
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([absoluteURL])
        }
        Divider()
        Button("Copy path") { copyToPasteboard(file.path) }
        Button("Copy filename") { copyToPasteboard(filename) }
    }

    private var absoluteURL: URL {
        viewModel.repository.url.appendingPathComponent(file.path)
    }

    private var filename: String {
        (file.path as NSString).lastPathComponent
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func toggleStaged() async {
        if file.isStaged { await viewModel.unstage([file]) }
        else             { await viewModel.stage([file]) }
    }

    /// Spoken status used by VoiceOver. Pairs the staged/unstaged side with
    /// its porcelain code so the user hears "Staged modified: path/to/file"
    /// instead of an opaque "checkbox marked".
    private var statusDescription: String {
        let side = file.isStaged ? "Staged" : "Unstaged"
        let status = file.isStaged ? file.stagedStatus : file.unstagedStatus
        return "\(side) \(status.spokenName)"
    }

    @ViewBuilder
    private var pathView: some View {
        if let originalPath = file.originalPath {
            renamedPathView(from: originalPath, to: file.path)
        } else {
            singlePathView(file.path)
        }
    }

    /// Standard `dim/dir/` + `bold name` rendering for non-rename rows.
    private func singlePathView(_ path: String) -> some View {
        let parts = path.split(separator: "/")
        let directory = parts.dropLast().joined(separator: "/")
        let name = parts.last.map(String.init) ?? path
        return HStack(spacing: DesignTokens.Spacing.none) {
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

    /// Renamed-row layout: `oldDir/ → newDir/name`. When both sides share a
    /// basename (the common case — file moved between directories) we show
    /// the directories around the arrow and append the basename once at the
    /// end. Different basenames render as `oldPath → newPath`.
    private func renamedPathView(from oldPath: String, to newPath: String) -> some View {
        let oldName = (oldPath as NSString).lastPathComponent
        let newName = (newPath as NSString).lastPathComponent
        let oldDir = (oldPath as NSString).deletingLastPathComponent
        let newDir = (newPath as NSString).deletingLastPathComponent
        let sameName = oldName == newName
        return HStack(spacing: DesignTokens.Spacing.xxs) {
            Text(sameName ? "\(oldDir)/" : oldPath)
                .font(AppFont.mono(11.5, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .lineLimit(1)
                .truncationMode(.head)
            Text("→")
                .font(AppFont.mono(11.5, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg4)
            if sameName {
                Text("\(newDir)/")
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(newName)
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
            } else {
                Text(newPath)
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }
}

extension StatusTag.Kind {
    /// Maps a working-copy status to the visual badge. `.unmodified` collapses
    /// to `.modified` so partially-staged files (where one side is unmodified)
    /// still render a badge instead of disappearing.
    init(workingFile: WorkingCopyFile.Status) {
        switch workingFile {
        case .modified, .typeChanged: self = .modified
        case .added:                  self = .added
        case .deleted:                self = .deleted
        case .renamed:                self = .renamed
        case .copied:                 self = .copied
        case .untracked:              self = .untracked
        case .unmerged:               self = .unmerged
        case .ignored:                self = .ignored
        case .unmodified:             self = .modified
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 0) {
        ForEach(WorkingCopyFile.previewSamples) { file in
            StagingRow(file: file, viewModel: .preview)
        }
    }
    .frame(width: 480)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
