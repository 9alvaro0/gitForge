import SwiftUI

/// `.gf-diff` — file diff viewer used in History and Changes.
struct DiffPane: View {
    let file: String?
    let hunks: [DiffHunk]
    var loading: Bool = false
    /// Optional handler for the "open in editor" icon button. When `nil` the
    /// button is hidden — keeps history-mode diffs free of dead chrome.
    var onOpenInEditor: (() -> Void)? = nil
    /// Optional handler for the close icon button. When `nil` the button is
    /// hidden — only History needs to collapse the diff pane.
    var onClose: (() -> Void)? = nil

    enum ViewMode: String, Hashable, CaseIterable, Identifiable {
        case unified, split
        var id: String { rawValue }
        var label: String {
            switch self {
            case .unified: return "Unified"
            case .split:   return "Split"
            }
        }
    }
    @Binding var viewMode: ViewMode

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(theme.palette.bg2)
        .overlay(alignment: .top) { Rectangle().fill(theme.palette.lineStrong).frame(height: 1) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                GFIcon(kind: .diff, size: 12, stroke: theme.palette.fg1)
                Text(file ?? "—")
                    .font(AppFont.mono(12, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            SegmentedControl<ViewMode>(
                [(.unified, "Unified"), (.split, "Split")],
                selection: $viewMode
            )
            if let onOpenInEditor {
                IconButton(.ext, action: onOpenInEditor)
                    .help("Open in editor")
            }
            if let onClose {
                IconButton(.x, action: onClose)
                    .help("Hide diff pane")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(theme.palette.bg1)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            diffSkeleton
        } else if hunks.isEmpty {
            Text("No changes")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewMode {
            case .unified: unifiedContent
            case .split:   splitContent
            }
        }
    }

    private static let placeholderHunk = DiffHunk(
        id: 0,
        oldStart: 1, oldCount: 7, newStart: 1, newCount: 8,
        header: "@@ -1,7 +1,8 @@ func loadData() {",
        lines: [
            DiffLine(id: 0, kind: .context, content: "    func loadData() async throws {",                      oldLineNumber: 1,    newLineNumber: 1),
            DiffLine(id: 1, kind: .context, content: "        let token = credentials.token(for: host)",        oldLineNumber: 2,    newLineNumber: 2),
            DiffLine(id: 2, kind: .removed, content: "        guard token != nil else { return }",              oldLineNumber: 3,    newLineNumber: nil),
            DiffLine(id: 3, kind: .added,   content: "        guard let token else { return }",                 oldLineNumber: nil,  newLineNumber: 3),
            DiffLine(id: 4, kind: .context, content: "        let response = try await fetcher.fetch()",        oldLineNumber: 4,    newLineNumber: 4),
            DiffLine(id: 5, kind: .added,   content: "        items = response.items",                          oldLineNumber: nil,  newLineNumber: 5),
            DiffLine(id: 6, kind: .added,   content: "        lastSync = Date()",                               oldLineNumber: nil,  newLineNumber: 6),
            DiffLine(id: 7, kind: .context, content: "        return items",                                    oldLineNumber: 5,    newLineNumber: 7),
            DiffLine(id: 8, kind: .context, content: "    }",                                                   oldLineNumber: 6,    newLineNumber: 8),
        ]
    )

    private var diffSkeleton: some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        hunkHeader(Self.placeholderHunk)
                        ForEach(Self.placeholderHunk.lines) { line in
                            DiffRow(line: line)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
        .skeleton(true)
    }

    private var unifiedContent: some View {
        // Two-level VStack: the inner one is `.fixedSize` vertically so rows
        // keep their natural height (no stretching when the diff is short),
        // and the outer one extends to the viewport with a trailing Spacer
        // that anchors the content to the top — preventing the bidirectional
        // ScrollView from centering it.
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(hunks) { hunk in
                            hunkHeader(hunk)
                            ForEach(hunk.lines) { line in
                                DiffRow(line: line)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
    }

    /// Side-by-side diff. `removed`+`context` on the left, `added`+`context`
    /// on the right, with consecutive removed / added groups paired so the
    /// changed lines align horizontally. Shorter side gets blank rows.
    private var splitContent: some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(hunks) { hunk in
                            hunkHeader(hunk)
                            ForEach(Array(splitRows(for: hunk).enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 0) {
                                    DiffSplitCell(line: row.left, side: .left)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Rectangle().fill(theme.palette.line).frame(width: 1)
                                    DiffSplitCell(line: row.right, side: .right)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
    }

    /// Pair consecutive `removed` runs with `added` runs so changed lines
    /// align side-by-side; pad the shorter run with blanks.
    private func splitRows(for hunk: DiffHunk) -> [SplitRow] {
        var out: [SplitRow] = []
        var pendingRemoved: [DiffLine] = []
        var pendingAdded: [DiffLine] = []

        func flush() {
            let count = max(pendingRemoved.count, pendingAdded.count)
            for i in 0..<count {
                out.append(SplitRow(
                    left:  i < pendingRemoved.count ? pendingRemoved[i] : nil,
                    right: i < pendingAdded.count   ? pendingAdded[i]   : nil
                ))
            }
            pendingRemoved.removeAll()
            pendingAdded.removeAll()
        }

        for line in hunk.lines {
            switch line.kind {
            case .context:
                flush()
                out.append(SplitRow(left: line, right: line))
            case .removed:
                pendingRemoved.append(line)
            case .added:
                pendingAdded.append(line)
            case .noNewline:
                // Marker — show on whichever side just had content.
                flush()
                out.append(SplitRow(left: line, right: line))
            }
        }
        flush()
        return out
    }

    private struct SplitRow {
        let left: DiffLine?
        let right: DiffLine?
    }

    @ViewBuilder
    private func hunkHeader(_ hunk: DiffHunk) -> some View {
        Text(hunk.header.isEmpty ? "@@" : hunk.header)
            .font(AppFont.mono(11, family: theme.monoFont))
            .foregroundStyle(theme.palette.fg3)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.bg3)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }
}

private struct DiffRow: View {
    let line: DiffLine
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            lineNumber(line.oldLineNumber)
            lineNumber(line.newLineNumber)
            Text(sign)
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .frame(width: 18)
                .foregroundStyle(signColor)
            Text(line.content.isEmpty ? " " : line.content)
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
    }

    @ViewBuilder
    private func lineNumber(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .font(AppFont.mono(11, family: theme.monoFont))
            .foregroundStyle(theme.palette.fg4)
            .frame(width: 44, alignment: .trailing)
            .padding(.horizontal, 8)
    }

    private var sign: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "−"
        case .context: return " "
        case .noNewline: return "\\"
        }
    }
    private var signColor: Color {
        switch line.kind {
        case .added:    return theme.palette.add
        case .removed:  return theme.palette.del
        case .context:  return theme.palette.fg3
        case .noNewline: return theme.palette.fg3
        }
    }
    private var textColor: Color {
        switch line.kind {
        case .added:   return theme.palette.add
        case .removed: return theme.palette.del
        default:       return theme.palette.fg2
        }
    }
    private var rowBackground: Color {
        switch line.kind {
        case .added:   return theme.palette.addSoft
        case .removed: return theme.palette.delSoft
        default:       return .clear
        }
    }
}

private struct DiffSplitCell: View {
    enum Side { case left, right }

    let line: DiffLine?
    let side: Side

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            lineNumber
            Text(sign)
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .frame(width: 18)
                .foregroundStyle(signColor)
            Text(displayContent)
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    @ViewBuilder
    private var lineNumber: some View {
        let number: Int? = {
            guard let line else { return nil }
            return side == .left ? line.oldLineNumber : line.newLineNumber
        }()
        Text(number.map(String.init) ?? "")
            .font(AppFont.mono(11, family: theme.monoFont))
            .foregroundStyle(theme.palette.fg4)
            .frame(width: 44, alignment: .trailing)
            .padding(.horizontal, 8)
    }

    private var displayContent: String {
        guard let line, !line.content.isEmpty else { return " " }
        return line.content
    }

    private var sign: String {
        guard let line else { return " " }
        switch line.kind {
        case .added:    return side == .right ? "+" : " "
        case .removed:  return side == .left  ? "−" : " "
        case .context:  return " "
        case .noNewline: return "\\"
        }
    }

    private var signColor: Color {
        guard let line else { return .clear }
        switch line.kind {
        case .added:    return theme.palette.add
        case .removed:  return theme.palette.del
        case .context:  return theme.palette.fg3
        case .noNewline: return theme.palette.fg3
        }
    }

    private var textColor: Color {
        guard let line else { return .clear }
        switch line.kind {
        case .added:   return theme.palette.add
        case .removed: return theme.palette.del
        default:       return theme.palette.fg2
        }
    }

    /// Standard split-diff convention: nil cells render as a muted gray
    /// "this line doesn't exist here" indicator — subtler than tinting them
    /// like a change so the actual changes still pop.
    private var background: Color {
        guard let line else { return theme.palette.bg3.opacity(0.5) }
        switch line.kind {
        case .added:   return theme.palette.addSoft
        case .removed: return theme.palette.delSoft
        default:       return .clear
        }
    }
}

#if DEBUG
#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    DiffPane(
        file: "src/components/CommitGraph.tsx",
        hunks: DiffHunk.previewSamples,
        viewMode: $mode
    )
    .frame(width: 720, height: 320)
    .background(theme.palette.bg2)
    .appTheme(theme)
}

#Preview("Loading") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    DiffPane(
        file: "src/Features/Repository/Pulls/PullsView.swift",
        hunks: [],
        loading: true,
        viewMode: $mode
    )
    .frame(width: 720, height: 320)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
#endif
