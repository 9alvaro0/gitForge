import SwiftUI

/// `.gf-view-conflict` — three-way picker for resolving conflicts.
struct ConflictView: View {
    let files: [ConflictFile]
    let hunks: [ConflictHunk]

    @Environment(\.appTheme) private var theme
    @State private var selectedPath: String = ""
    @State private var picks: [UUID: ConflictHunk.Pick] = [:]

    init(files: [ConflictFile] = ConflictFile.previewSamples,
         hunks: [ConflictHunk] = ConflictHunk.previewSamples) {
        self.files = files
        self.hunks = hunks
        _selectedPath = State(initialValue: files.first?.path ?? "")
    }

    private var resolvedCount: Int { picks.count }

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Resolve conflicts") {
                MonoText("merging origin/main into feat/commit-graph", dim: true)
            } right: {
                ToolButton(.x, label: "Abort merge") { }
                ToolButton(.check, label: "Continue merge", primary: true,
                           disabled: resolvedCount < hunks.count) { }
            }
            HStack(spacing: 0) {
                filesColumn
                hunksColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    private var filesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Files with conflicts".uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(theme.palette.fg3)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            ForEach(files) { file in
                Button(action: { selectedPath = file.path }) {
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
                    .background(RoundedRectangle(cornerRadius: 5).fill(file.path == selectedPath ? theme.palette.bg4 : .clear))
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
                HStack(spacing: 8) {
                    GFIcon(kind: .diff, size: 14, stroke: theme.palette.fg1)
                    Text(selectedPath)
                        .font(AppFont.mono(12, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg1)
                    Text("· \(resolvedCount)/\(hunks.count) resolved")
                        .font(AppFont.mono(12, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                }
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }

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
                    Pill(text: "resolved → \(pick.rawValue)", kind: .clean)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(theme.palette.bg2)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }

            HStack(spacing: 0) {
                conflictPane(title: "ours",   subtitle: "feat/commit-graph", lines: hunk.ours,   isPicked: pick == .ours,   tagColor: theme.palette.add) {
                    picks[hunk.id] = .ours
                }
                Rectangle().fill(theme.palette.line).frame(width: 1)
                conflictPane(title: "both",   subtitle: "merge manually",     lines: hunk.base,   isPicked: pick == .both,   tagColor: theme.palette.mod) {
                    picks[hunk.id] = .both
                }
                Rectangle().fill(theme.palette.line).frame(width: 1)
                conflictPane(title: "theirs", subtitle: "origin/main",        lines: hunk.theirs, isPicked: pick == .theirs, tagColor: theme.palette.info) {
                    picks[hunk.id] = .theirs
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

#Preview {
    @Previewable @State var theme = AppTheme()
    ConflictView(files: ConflictFile.previewSamples,
                 hunks: ConflictHunk.previewSamples)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
