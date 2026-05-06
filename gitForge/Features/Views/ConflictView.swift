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
        VStack(spacing: 0) {
            ContentHeader(title: "Resolve conflicts") {
                MonoText(headerSubtitle, dim: true)
            } right: {
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
            HStack(spacing: 0) {
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
        case .clean:    return ""
        }
    }

    private var filesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Files with conflicts".uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(theme.palette.fg3)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            if files.isEmpty {
                Text("No unresolved files.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
                    .padding(14)
            }
            ForEach(files) { file in
                Button(action: { Task { await viewModel.loadConflictHunks(for: file.path) } }) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill((file.resolved ? theme.palette.ok : theme.palette.del).opacity(0.18))
                            Text(file.resolved ? "✓" : "!")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(file.resolved ? theme.palette.ok : theme.palette.del)
                        }
                        .frame(width: 18, height: 18)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 5).fill(file.path == viewModel.selectedConflictPath ? theme.palette.bg4 : .clear))
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: DesignTokens.Conflict.filesWidth)
        .background(theme.palette.bg1)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.palette.lineStrong).frame(width: 1) }
    }

    private var hunksColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let path = viewModel.selectedConflictPath {
                    HStack(spacing: 8) {
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
                    .padding(.bottom, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
                }

                if hunks.isEmpty {
                    Text("Pick a file with unresolved conflicts on the left.")
                        .font(AppFont.sans(12))
                        .foregroundStyle(theme.palette.fg3)
                        .padding(.top, 8)
                }

                ForEach(Array(hunks.enumerated()), id: \.element.id) { index, hunk in
                    hunkCard(hunk, index: index)
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func hunkCard(_ hunk: ConflictHunk, index: Int) -> some View {
        let pick = picks[hunk.id]
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Conflict #\(index + 1)")
                    .font(AppFont.mono(12, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                Spacer()
                if let pick {
                    Pill(text: "picked → \(pick.rawValue)", kind: .clean)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(theme.palette.bg2)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }

            HStack(spacing: 0) {
                conflictPane(title: "ours", subtitle: viewModel.currentBranchName ?? "HEAD", lines: hunk.ours,
                             isPicked: pick == .ours, tagColor: theme.palette.add) {
                    viewModel.setConflictPick(hunkId: hunk.id, pick: .ours)
                }
                Rectangle().fill(theme.palette.line).frame(width: 1)
                conflictPane(title: "both", subtitle: "ours + theirs", lines: hunk.base.isEmpty ? hunk.ours + hunk.theirs : hunk.base,
                             isPicked: pick == .both, tagColor: theme.palette.mod) {
                    viewModel.setConflictPick(hunkId: hunk.id, pick: .both)
                }
                Rectangle().fill(theme.palette.line).frame(width: 1)
                conflictPane(title: "theirs", subtitle: "incoming", lines: hunk.theirs,
                             isPicked: pick == .theirs, tagColor: theme.palette.info) {
                    viewModel.setConflictPick(hunkId: hunk.id, pick: .theirs)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: 1))
        .opacity(pick == nil ? 1 : 0.85)
    }

    @ViewBuilder
    private func conflictPane(title: String, subtitle: String, lines: [String], isPicked: Bool, tagColor: Color, onPick: @escaping () -> Void) -> some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(AppFont.mono(10.5, weight: .medium, family: theme.monoFont))
                        .foregroundStyle(tagColor)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(tagColor.opacity(0.18)))
                    Text(subtitle).font(AppFont.mono(11, family: theme.monoFont)).foregroundStyle(theme.palette.fg3)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isPicked ? theme.palette.accent.opacity(0.10) : .clear)
            .overlay(alignment: .bottom) {
                if isPicked { Rectangle().fill(theme.palette.accent).frame(height: 2) }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Empty (clean tree)") {
    @Previewable @State var theme = AppTheme()
    ConflictView(viewModel: RepositoryViewModel.preview)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
