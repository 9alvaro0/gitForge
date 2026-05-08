import SwiftUI

/// `.gf-view-conflict` — three-way conflict resolver. Reads conflict state
/// from the active `RepositoryViewModel`; falls back to a friendly empty state
/// when the working tree is clean.
struct ConflictView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme

    private var files: [ConflictFile]   { viewModel.conflictFiles }
    private var hunks: [ConflictHunk]   { viewModel.conflictHunks }
    private var picks: [UUID: ConflictHunk.Pick] { viewModel.conflictPicks }

    var body: some View {
        Group {
            if !viewModel.mergeState.isInProgress {
                EmptyState(icon: .check, title: "No merge in progress",
                           subtitle: "Conflicts will show up here when a merge or rebase pauses.") { EmptyView() }
                    .background(theme.palette.bg2)
            } else {
                resolverShell
            }
        }
        .task { await viewModel.loadConflictState() }
    }

    private var resolverShell: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ContentHeader(title: "Resolve conflicts") {
                MonoText(headerSubtitle, dim: true)
            } right: {
                // `.unmerged` (stash apply conflict) has no native abort /
                // continue commands — the user resolves files and commits
                // normally. Hide both buttons in that case.
                if viewModel.mergeState != .unmerged {
                    ToolButton(.x, label: "Abort \(viewModel.mergeState == .rebasing ? "rebase" : "merge")") {
                        Task { await viewModel.abortMerge() }
                    }
                    ToolButton(.check,
                               label: "Continue \(viewModel.mergeState == .rebasing ? "rebase" : "merge")",
                               primary: true,
                               disabled: !files.allSatisfy(\.resolved)) {
                        Task { await viewModel.continueMerge() }
                    }
                }
            }
            HStack(spacing: DesignTokens.Spacing.none) {
                filesColumn
                hunksColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    private var headerSubtitle: String {
        switch viewModel.mergeState {
        case .merging:  return "merging into \(viewModel.currentBranchName ?? "HEAD")"
        case .rebasing: return "rebasing \(viewModel.currentBranchName ?? "HEAD")"
        case .unmerged: return "applying stash on \(viewModel.currentBranchName ?? "HEAD")"
        case .clean:    return ""
        }
    }

    private var filesColumn: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
            Text("Files with conflicts".uppercased())
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(theme.palette.fg3)
                .padding(.horizontal, DesignTokens.Spacing.xxl)
                .padding(.vertical, DesignTokens.Spacing.md)
            if files.isEmpty {
                Text("No unresolved files.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
                    .padding(DesignTokens.Spacing.xxl)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                        ForEach(files) { file in
                            conflictFileRow(file)
                        }
                    }
                }
            }
        }
        .frame(width: DesignTokens.Conflict.filesWidth)
        .background(theme.palette.bg1)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.palette.lineStrong).frame(width: DesignTokens.Stroke.regular) }
    }

    @ViewBuilder
    private func conflictFileRow(_ file: ConflictFile) -> some View {
        Button(action: { Task { await viewModel.loadConflictHunks(for: file.path) } }) {
            HStack(spacing: DesignTokens.Spacing.md) {
                ZStack {
                    Circle().fill((file.resolved ? theme.palette.ok : theme.palette.del).opacity(DesignTokens.Opacity.muted))
                    Text(file.resolved ? "✓" : "!")
                        .font(.system(size: FontSize.footnote, weight: .bold))
                        .foregroundStyle(file.resolved ? theme.palette.ok : theme.palette.del)
                }
                .frame(width: DesignTokens.IconSize.xl, height: DesignTokens.IconSize.xl)
                Text(file.path)
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(file.resolved ? theme.palette.fg3 : theme.palette.fg1)
                    .strikethrough(file.resolved)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(file.conflicts)")
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(file.path == viewModel.selectedConflictPath ? theme.palette.bg4 : .clear))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.sm))
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
        .buttonStyle(.plain)
        .contextMenu { conflictRowMenu(file) }
    }

    @ViewBuilder
    private func conflictRowMenu(_ file: ConflictFile) -> some View {
        if !file.resolved {
            Button("Resolve using ours") {
                Task { await viewModel.resolveFile(at: file.path, using: .ours) }
            }
            Button("Resolve using theirs") {
                Task { await viewModel.resolveFile(at: file.path, using: .theirs) }
            }
            Button("Discard conflict (revert to HEAD)", role: .destructive) {
                Task { await viewModel.discardChanges(workingCopyFile(for: file)) }
            }
            Divider()
        }
        Button("Open in editor") {
            NSWorkspace.shared.open(absoluteURL(for: file))
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([absoluteURL(for: file)])
        }
        Divider()
        Button("Copy path") { copyToPasteboard(file.path) }
        Button("Copy filename") { copyToPasteboard((file.path as NSString).lastPathComponent) }
    }

    private func absoluteURL(for file: ConflictFile) -> URL {
        viewModel.repository.url.appendingPathComponent(file.path)
    }

    /// Builds an array compatible with `viewModel.discardChanges([WorkingCopyFile])`
    /// from a `ConflictFile` so the unmerged-aware discard path is reused.
    private func workingCopyFile(for file: ConflictFile) -> [WorkingCopyFile] {
        guard let match = viewModel.status.files.first(where: { $0.path == file.path }) else {
            return []
        }
        return [match]
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }

    private var hunksColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxl) {
                if let path = viewModel.selectedConflictPath {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        GFIcon(kind: .diff, size: 14, stroke: theme.palette.fg1)
                        Text(path)
                            .font(AppFont.mono(12, family: theme.monoFont))
                            .foregroundStyle(theme.palette.fg1)
                        Text("· \(picks.count)/\(hunks.count) picked")
                            .font(AppFont.mono(12, family: theme.monoFont))
                            .foregroundStyle(theme.palette.fg3)
                        Spacer()
                        GFButton(title: "Mark resolved",
                                 style: .primary,
                                 size: .small,
                                 disabled: hunks.isEmpty || picks.count < hunks.count) {
                            Task { await viewModel.resolveSelectedFile() }
                        }
                    }
                    .padding(.bottom, DesignTokens.Spacing.md)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
                }

                if hunks.isEmpty {
                    Text("Pick a file with unresolved conflicts on the left.")
                        .font(AppFont.sans(12))
                        .foregroundStyle(theme.palette.fg3)
                        .padding(.top, DesignTokens.Spacing.md)
                }

                ForEach(Array(hunks.enumerated()), id: \.element.id) { index, hunk in
                    hunkCard(hunk, index: index)
                }
            }
            .padding(DesignTokens.Spacing.xxxxl)
        }
    }

    @ViewBuilder
    private func hunkCard(_ hunk: ConflictHunk, index: Int) -> some View {
        let pick = picks[hunk.id]
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text("Conflict #\(index + 1)")
                    .font(AppFont.mono(12, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                Text("· \(hunk.ours.count) vs \(hunk.theirs.count) lines")
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
                Spacer()
                if let pick {
                    Pill(text: "picked → \(pick.rawValue)", kind: .neutral)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xl).padding(.vertical, DesignTokens.Spacing.md)
            .background(theme.palette.bg2)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }

            ConflictSection(
                title: "ours",
                subtitle: viewModel.currentBranchName ?? "HEAD",
                lines: hunk.ours,
                tagColor: theme.palette.add,
                rowBackground: theme.palette.addSoft,
                isPicked: pick == .ours,
                actionLabel: "Pick ours",
                onPick: { viewModel.setConflictPick(hunkId: hunk.id, pick: .ours) }
            )
            Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular)
            ConflictSection(
                title: "theirs",
                subtitle: "incoming",
                lines: hunk.theirs,
                tagColor: theme.palette.info,
                rowBackground: theme.palette.info.opacity(DesignTokens.Opacity.subtle),
                isPicked: pick == .theirs,
                actionLabel: "Pick theirs",
                onPick: { viewModel.setConflictPick(hunkId: hunk.id, pick: .theirs) }
            )
            Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular)
            // "Both" is rare enough that it lives as a footer action rather
            // than a third visual pane — keeps the card focused on ours/theirs.
            HStack(spacing: DesignTokens.Spacing.md) {
                Button {
                    viewModel.setConflictPick(hunkId: hunk.id, pick: .both)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        GFIcon(kind: .plus, size: 11, stroke: pick == .both ? theme.palette.accent : theme.palette.fg2)
                        Text("Pick both (ours + theirs)")
                            .font(AppFont.sans(11.5, weight: pick == .both ? .medium : .regular))
                            .foregroundStyle(pick == .both ? theme.palette.accent : theme.palette.fg2)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg).padding(.vertical, DesignTokens.Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(pick == .both ? theme.palette.accent.opacity(DesignTokens.Opacity.subtle) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .stroke(pick == .both ? theme.palette.accent : theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
                    .contentShape(.rect(cornerRadius: DesignTokens.Radius.sm))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(theme.palette.bg2)

            // Result preview — what gets written when "Mark resolved" runs.
            // Lives here so the user can verify combined picks (especially
            // "both") before committing.
            Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular)
            ConflictSection(
                title: "result",
                subtitle: resultSubtitle(for: pick, hunk: hunk),
                lines: resultLines(for: pick, hunk: hunk),
                tagColor: theme.palette.accent,
                rowBackground: theme.palette.accent.opacity(DesignTokens.Opacity.subtle),
                isPicked: false,
                actionLabel: nil,
                onPick: nil,
                emptyMessage: "Pick a side above to preview the merged result."
            )
        }
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func resultSubtitle(for pick: ConflictHunk.Pick?, hunk: ConflictHunk) -> String {
        guard let pick else { return "no pick yet" }
        switch pick {
        case .ours:   return "from ours · \(hunk.ours.count) lines"
        case .theirs: return "from theirs · \(hunk.theirs.count) lines"
        case .both:   return "ours + theirs · \(hunk.ours.count + hunk.theirs.count) lines"
        }
    }

    private func resultLines(for pick: ConflictHunk.Pick?, hunk: ConflictHunk) -> [String] {
        guard let pick else { return [] }
        switch pick {
        case .ours:   return hunk.ours
        case .theirs: return hunk.theirs
        case .both:   return hunk.ours + hunk.theirs
        }
    }
}

/// One side of a conflict (`ours` or `theirs`) rendered with the same row
/// aesthetic as `DiffPane`: line-number gutter, monospaced grid, soft tinted
/// background, horizontal scroll for long lines. The pick button lives in the
/// section header so the action is always reachable.
private struct ConflictSection: View {
    let title: String
    let subtitle: String
    let lines: [String]
    let tagColor: Color
    let rowBackground: Color
    let isPicked: Bool
    /// Action button shown in the section header. Pass `nil` for read-only
    /// sections like the result preview.
    var actionLabel: String? = nil
    var onPick: (() -> Void)? = nil
    /// Copy shown when `lines` is empty. Defaults to a generic "no lines"
    /// note suitable for ours/theirs sections.
    var emptyMessage: String = "(no lines on this side)"

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
            sectionHeader
            content
        }
        .background(theme.palette.bg1)
        .overlay(alignment: .leading) {
            if isPicked {
                Rectangle().fill(tagColor).frame(width: 3)
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text(title)
                .font(AppFont.mono(10.5, weight: .medium, family: theme.monoFont))
                .foregroundStyle(tagColor)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.hairline)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(tagColor.opacity(DesignTokens.Opacity.muted)))
            Text(subtitle)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
            Spacer()
            if let actionLabel, let onPick {
                Button(action: onPick) {
                    Text(actionLabel)
                        .font(AppFont.sans(11.5, weight: .medium))
                        .foregroundStyle(isPicked ? .white : tagColor)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(isPicked ? tagColor : tagColor.opacity(DesignTokens.Opacity.subtle)))
                        .contentShape(.rect(cornerRadius: DesignTokens.Radius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
    }

    @ViewBuilder
    private var content: some View {
        if lines.isEmpty {
            Text(emptyMessage)
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .italic()
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.md)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        ConflictLineRow(lineNumber: index + 1, content: line, background: rowBackground)
                    }
                }
            }
        }
    }
}

private struct ConflictLineRow: View {
    let lineNumber: Int
    let content: String
    let background: Color

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.none) {
            Text("\(lineNumber)")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg4)
                .frame(width: 36, alignment: .trailing)
                .padding(.horizontal, DesignTokens.Spacing.md)
            Text(content.isEmpty ? " " : content)
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, DesignTokens.Spacing.xxl)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }
}

#if DEBUG
#Preview("Empty (clean tree)") {
    @Previewable @State var theme = AppTheme()
    ConflictView(viewModel: RepositoryViewModel.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
#endif
