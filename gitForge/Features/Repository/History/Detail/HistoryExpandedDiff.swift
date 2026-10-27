import SwiftUI

/// History's diff filling the whole pane, for reading a change with room
/// (audit H2). A bar on top names the selection and steps through its files
/// (⌥⌘↑ / ⌥⌘↓); Esc, ⇧⌘↩ or the diff header's button go back.
struct HistoryExpandedDiff: View {
    @Bindable var viewModel: RepositoryViewModel
    let isUncommittedSelected: Bool
    let diffMode: Binding<DiffPane.ViewMode>
    let onExit: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            bar
            HistoryDiffPane(
                viewModel: viewModel,
                isUncommittedSelected: isUncommittedSelected,
                diffMode: diffMode,
                isExpanded: true,
                onToggleExpand: onExit
            )
        }
    }

    private var bar: some View {
        let files = fileList
        let position = DiffFileNavigation.position(of: files.current, in: files.ids)
        return HStack(spacing: Spacing.s8) {
            Button(action: onExit) {
                HStack(spacing: Spacing.s4) {
                    SymbolGlyph("chevron.backward", size: 11)
                    Text("History")
                }
                .padding(.horizontal, Spacing.s6)
                .frame(height: 24)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.colors.accent)
            .keyboardShortcut(.cancelAction)
            .help("Back to History (Esc)")
            Text(title)
                .textRole(.callout, weight: .medium)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let shortSha = viewModel.history.selectedCommit?.shortSha, !isUncommittedSelected {
                Text(shortSha)
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            Spacer(minLength: Spacing.s8)
            if let position {
                Text(String(localized: "File \(position.index + 1) of \(position.count)"))
                    .textRole(.caption)
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize()
            }
            stepButton(symbol: "chevron.up", label: String(localized: "Previous file"),
                       shortcut: .upArrow, hint: "⌥⌘↑", target: DiffFileNavigation.neighbor(of: files.current, in: files.ids, offset: -1),
                       select: files.select)
            stepButton(symbol: "chevron.down", label: String(localized: "Next file"),
                       shortcut: .downArrow, hint: "⌥⌘↓", target: DiffFileNavigation.neighbor(of: files.current, in: files.ids, offset: 1),
                       select: files.select)
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: 36)
        .background(theme.colors.bgContent)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
    }

    private func stepButton(symbol: String, label: String, shortcut: KeyEquivalent, hint: String, target: String?,
                            select: @escaping (String) -> Void) -> some View {
        IconButton(symbol: symbol, size: 12, accessibilityLabel: label) {
            if let target { select(target) }
        }
        .keyboardShortcut(shortcut, modifiers: [.option, .command])
        .disabled(target == nil)
        .help(Text(verbatim: "\(label) (\(hint))"))
    }

    private var title: String {
        if isUncommittedSelected { return String(localized: "Uncommitted changes") }
        return viewModel.history.selectedCommit?.subject ?? ""
    }

    /// The selection's files in the inspector's order, as ids, with the open
    /// one and how to open another. Working-copy files carry their side: a
    /// file with staged and unstaged changes appears twice.
    private var fileList: (ids: [String], current: String?, select: (String) -> Void) {
        if isUncommittedSelected {
            let workingCopy = viewModel.workingCopy
            let staged = workingCopy.status.stagedFiles
            let unstaged = workingCopy.status.unstagedFiles
            let rows = staged.map { WorkingCopyRowID(side: .staged, path: $0.path) }
                + unstaged.map { WorkingCopyRowID(side: .unstaged, path: $0.path) }
            let key = { (row: WorkingCopyRowID) in "\(row.side == .staged ? "s" : "u"):\(row.path)" }
            return (rows.map(key), workingCopy.selectedRowID.map(key), { id in
                guard let row = rows.first(where: { key($0) == id }) else { return }
                workingCopy.select(row, in: row.side == .staged ? staged : unstaged)
            })
        }
        let history = viewModel.history
        let paths = history.selectedCommit.flatMap { history.detailCache[$0.sha] }?.files.map(\.path) ?? []
        return (paths, history.selectedCommitFile, { history.selectedCommitFile = $0 })
    }
}

/// Stepping through a list of files from the open one.
nonisolated enum DiffFileNavigation {
    /// The file `offset` places from `current`, or `nil` past either end.
    /// With nothing open, stepping forward opens the first file.
    static func neighbor(of current: String?, in ids: [String], offset: Int) -> String? {
        guard let current, let index = ids.firstIndex(of: current) else {
            return offset > 0 ? ids.first : nil
        }
        let target = index + offset
        return ids.indices.contains(target) ? ids[target] : nil
    }

    /// Where `current` sits in `ids`, for "File 3 of 12".
    static func position(of current: String?, in ids: [String]) -> (index: Int, count: Int)? {
        guard let current, let index = ids.firstIndex(of: current) else { return nil }
        return (index, ids.count)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    let vm: RepositoryViewModel = {
        let v = RepositoryViewModel.preview
        v.history.selectedCommitId = v.history.commits.first?.sha
        return v
    }()
    HistoryExpandedDiff(viewModel: vm, isUncommittedSelected: false, diffMode: $mode, onExit: {})
        .previewAppState(.preview)
        .frame(width: 1100, height: 640)
        .appTheme(theme)
}
