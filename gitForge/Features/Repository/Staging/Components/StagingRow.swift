import SwiftUI
import AppKit

struct StagingRow: View {
    let file: WorkingCopyFile
    @Bindable var viewModel: RepositoryViewModel
    /// The list the row sits in; a file with staged and unstaged changes
    /// appears in both, each opening its own part of the diff.
    var side: WorkingCopySide? = nil
    /// `+N −M` of this row's side (staged or unstaged), when git reports it.
    var lineCounts: DiffStats? = nil
    /// Runs after a click opens the row — the list takes keyboard focus.
    var onSelect: (() -> Void)? = nil
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    /// Drives a per-row confirmation when the user picks "Discard changes"
    /// or "Delete file" on an untracked entry. Always confirms — there's no
    /// undo for this and the all-files variant already gates behind a dialog.
    @State private var pendingDiscard = false

    var body: some View {
        let isSelected = viewModel.workingCopy.selectedWorkingCopyFile?.id == file.id
            && (side == nil || viewModel.workingCopy.diffSide(for: file) == side)
        let isTicked = viewModel.workingCopy.selectedFilePaths.contains(file.path)
        Button(action: {
            viewModel.workingCopy.select(file, side: side)
            onSelect?()
        }) {
            HStack(spacing: Spacing.s8) {
                // The checkbox is for *batch selection*, not stage/unstage —
                // pairing it with the batch bar under the section. Stage /
                // unstage on a single row stays available via double-click
                // and the context menu.
                Toggle("", isOn: Binding(
                    get: { isTicked },
                    set: { _ in viewModel.workingCopy.toggleSelection(file) }
                ))
                .toggleStyle(GFCheckboxStyle())
                .accessibilityLabel("Select \(file.path)")
                .accessibilityValue(isTicked ? String(localized: "selected") : String(localized: "not selected"))
                StatusTag(kind: StatusTag.Kind(workingFile: file.displayStatus))
                pathView
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let lineCounts, !lineCounts.isEmpty {
                    countsView(lineCounts)
                }
            }
            .padding(.leading, Spacing.s8)
            .padding(.trailing, Spacing.s12)
            .frame(height: theme.density.metrics.rowList)
            .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowFill(isSelected: isSelected, isTicked: isTicked)))
            .contentShape(.rect(cornerRadius: Radius.row))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { Task { await toggleStaged() } }
        )
        .help(showsStagedSide ? String(localized: "Double-click to unstage · checkbox = select for batch") : String(localized: "Double-click to stage · checkbox = select for batch"))
        .contextMenu { contextMenu }
        .confirmationDialog(
            file.isUntracked ? String(localized: "Delete \(filename)?") : String(localized: "Discard changes to \(filename)?"),
            isPresented: $pendingDiscard,
            titleVisibility: .visible
        ) {
            Button(file.isUntracked ? String(localized: "Delete file") : String(localized: "Discard changes"),
                   role: .destructive) {
                Task { await viewModel.discardChanges([file]) }
            }
        } message: {
            Text(file.isUntracked
                 ? String(localized: "The file will be removed from disk. This can't be undone from the app.")
                 : String(localized: "Local changes will be reverted to the last committed version. This can't be undone."))
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if showsStagedSide {
            Button("Unstage") { Task { await viewModel.unstage([file]) } }
        } else {
            Button("Stage") { Task { await viewModel.stage([file]) } }
        }
        if file.isUntracked {
            Button("Delete file", role: .destructive) {
                pendingDiscard = true
            }
        } else {
            Button(file.isUnmerged ? String(localized: "Discard conflict (revert to HEAD)") : String(localized: "Discard changes"),
                   role: .destructive) {
                pendingDiscard = true
            }
        }
        Divider()
        Button("Open in editor") {
            ExternalURL.openFile(absoluteURL)
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([absoluteURL])
        }
        Divider()
        Button("Copy path") { copyToPasteboard(file.path) }
        Button("Copy filename") { copyToPasteboard(filename) }
    }

    /// The file whose diff is open takes the accent; ticked and hovered rows
    /// a neutral fill.
    private func rowFill(isSelected: Bool, isTicked: Bool) -> Color {
        if isSelected { return theme.colors.accentSoft }
        if isTicked || hovering { return theme.colors.fillHover }
        return .clear
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
        if showsStagedSide { await viewModel.unstage([file]) }
        else               { await viewModel.stage([file]) }
    }

    /// In the Staged list the row's actions unstage; in Unstaged they stage,
    /// even for a file that also has staged changes.
    private var showsStagedSide: Bool {
        side.map { $0 == .staged } ?? file.isStaged
    }

    /// Spoken status used by VoiceOver. Pairs the staged/unstaged side with
    /// its porcelain code so the user hears "Staged modified: path/to/file"
    /// instead of an opaque "checkbox marked".
    private var statusDescription: String {
        let status = file.isStaged ? file.stagedStatus : file.unstagedStatus
        let spoken = status.spokenName
        return file.isStaged ? String(localized: "Staged \(spoken)") : String(localized: "Unstaged \(spoken)")
    }

    private var accessibilityText: String {
        let base = "\(statusDescription): \(file.path)"
        guard let lineCounts, !lineCounts.isEmpty else { return base }
        let additions = lineCounts.additions
        let deletions = lineCounts.deletions
        return String(localized: "\(base), \(additions) additions, \(deletions) deletions")
    }

    private func countsView(_ counts: DiffStats) -> some View {
        HStack(spacing: Spacing.s4) {
            if counts.additions > 0 {
                Text("+\(counts.additions)").foregroundStyle(theme.colors.add)
            }
            if counts.deletions > 0 {
                Text("−\(counts.deletions)").foregroundStyle(theme.colors.del)
            }
        }
        .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
        .lineLimit(1)
        .fixedSize()
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
        return HStack(spacing: 0) {
            if !directory.isEmpty {
                Text("\(directory)/")
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textQuaternary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(name)
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textPrimary)
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
        return HStack(spacing: Spacing.s2) {
            Text(sameName ? "\(oldDir)/" : oldPath)
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textQuaternary)
                .lineLimit(1)
                .truncationMode(.head)
            Text("→")
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textQuaternary)
            if sameName {
                Text("\(newDir)/")
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textQuaternary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(newName)
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
            } else {
                Text(newPath)
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
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
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
