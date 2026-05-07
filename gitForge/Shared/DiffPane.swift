import SwiftUI

/// `.gf-diff` — file diff viewer used in History and Changes.
struct DiffPane: View {
    let file: String?
    let hunks: [DiffHunk]
    var loading: Bool = false
    /// Optional handler for the "open in editor" icon button. When `nil` the
    /// button is hidden — keeps history-mode diffs free of dead chrome.
    var onOpenInEditor: (() -> Void)? = nil

    enum ViewMode: Hashable { case unified, split }
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
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hunks.isEmpty {
            Text("No changes")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(hunks) { hunk in
                        hunkHeader(hunk)
                        ForEach(hunk.lines) { line in
                            DiffRow(line: line)
                        }
                    }
                }
                .frame(minWidth: 1, alignment: .leading)
            }
        }
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
        }
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

#Preview {
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
