import SwiftUI

/// File diff viewer used in History and Changes.
struct DiffPane: View {
    let file: String?
    let hunks: [DiffHunk]
    var loading: Bool = false
    /// Reason the diff is empty when `hunks.isEmpty`. Drives the empty-state
    /// copy so binaries / renames don't masquerade as "No changes".
    var emptyState: DiffEmptyState = .empty
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

    /// `hunk.id → line.id → AttributedString`. While empty, rows fall back
    /// to plain `Text(content)` — kind-based foreground colouring carries
    /// the UX until tokenisation settles.
    @State private var highlighted: [Int: [Int: AttributedString]] = [:]

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            DiffHeader(
                file: file,
                viewMode: $viewMode,
                onOpenInEditor: onOpenInEditor,
                onClose: onClose
            )
            content
        }
        .background(theme.palette.bg2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.palette.lineStrong)
                .frame(height: DesignTokens.Stroke.regular)
        }
        .task(id: tokenizeKey) { await tokenizeHunks() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            DiffLoadingSkeleton()
        } else if hunks.isEmpty {
            DiffEmptyContent(state: emptyState)
        } else {
            switch viewMode {
            case .unified: DiffUnifiedContent(hunks: hunks, highlighted: highlighted)
            case .split:   DiffSplitContent(hunks: hunks, highlighted: highlighted)
            }
        }
    }

    /// Re-tokenises when file, hunks, theme mode, or accent change —
    /// everything the cached attributed strings depend on.
    private var tokenizeKey: String {
        "\(file ?? "")|\(hunks.map { "\($0.id):\($0.lines.count)" }.joined(separator: ","))|\(theme.mode.rawValue)|\(theme.accent.cssHex)"
    }

    private func tokenizeHunks() async {
        guard let language = DiffSyntaxHighlighter.languageId(for: file), !hunks.isEmpty else {
            highlighted = [:]
            return
        }
        let css = DiffSyntaxHighlighter.css(for: theme.palette)
        let themeId = "\(theme.mode.rawValue)-\(theme.accent.cssHex)"
        let snapshot = hunks
        var output: [Int: [Int: AttributedString]] = [:]
        for hunk in snapshot {
            let lines = await DiffSyntaxHighlighter.shared.tokenize(
                hunk: hunk,
                language: language,
                css: css,
                themeId: themeId
            )
            if !lines.isEmpty { output[hunk.id] = lines }
            if Task.isCancelled { return }
        }
        highlighted = output
    }
}

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

#Preview("Split") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .split
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

#Preview("Empty (binary)") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    DiffPane(
        file: "assets/logo.png",
        hunks: [],
        emptyState: .binary,
        viewMode: $mode
    )
    .frame(width: 720, height: 320)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
