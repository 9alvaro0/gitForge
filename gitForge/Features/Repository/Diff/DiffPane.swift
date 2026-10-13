import SwiftUI

/// File diff viewer used in History and Changes.
struct DiffPane: View {
    let file: String?
    /// Change kind of `file`, shown as the header badge when the host knows it.
    var status: StatusTag.Kind? = nil
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
    /// Re-reads the diff when Hide whitespace flips. When `nil` the option
    /// isn't offered: the diff doesn't come from git (pull requests).
    var onWhitespaceChange: (() -> Void)? = nil
    /// Stage / unstage / discard per hunk or picked lines (Changes). When
    /// `nil` the headers carry no buttons and lines can't be picked.
    var hunkActions: DiffHunkActions? = nil
    /// Reads the new side of the file for "Show N hidden lines". When `nil`
    /// (or it returns `nil`) no gap rows show.
    var loadNewSide: (() async -> [String]?)? = nil

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
    @Environment(\.appPreferences) private var preferences

    /// `hunk.id → line.id → AttributedString`. While empty, rows fall back
    /// to plain `Text(content)` — kind-based foreground colouring carries
    /// the UX until tokenisation settles.
    @State private var highlighted: [Int: [Int: AttributedString]] = [:]
    /// `hunk.id → picked line ids`. Cleared whenever the diff changes: line
    /// ids are positions in the hunk, so they'd point elsewhere.
    @State private var selectedLines: [Int: Set<Int>] = [:]
    /// A discard waiting for confirmation.
    @State private var pendingDiscard: PendingDiscard?
    /// New side of the file, loaded once the hunks are in.
    @State private var fileLines: [String]?
    /// Ids of the gaps the user opened.
    @State private var expandedGaps: Set<Int> = []

    private struct PendingDiscard {
        let hunk: DiffHunk
        let lineIds: Set<Int>?
    }

    var body: some View {
        VStack(spacing: 0) {
            DiffHeader(
                file: file,
                status: status,
                stats: loading || hunks.isEmpty ? nil : DiffStats(hunks: hunks),
                viewMode: $viewMode,
                canHideWhitespace: onWhitespaceChange != nil,
                onOpenInEditor: onOpenInEditor,
                onClose: onClose
            )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.colors.bgCode)
        .task(id: tokenizeKey) { await tokenizeHunks() }
        .onChange(of: selectionKey) { selectedLines = [:] }
        .task(id: selectionKey) { await loadFileLines() }
        .confirmationDialog(discardTitle, isPresented: discardBinding, titleVisibility: .visible) {
            Button("Cancel", role: .cancel) { pendingDiscard = nil }
                .keyboardShortcut(.defaultAction)
            Button("Discard", role: .destructive) {
                if let pending = pendingDiscard { hunkActions?.onDiscard?(pending.hunk, pending.lineIds) }
                pendingDiscard = nil
            }
        } message: {
            Text("These changes will be lost from the working tree. This can't be undone.")
        }
        .onChange(of: preferences.diffIgnoreWhitespace) { onWhitespaceChange?() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            DiffLoadingSkeleton()
        } else if hunks.isEmpty {
            DiffEmptyContent(state: emptyState)
        } else {
            switch viewMode {
            case .unified:
                DiffUnifiedContent(hunks: hunks, highlighted: highlighted,
                                   selectedLines: selectedLines,
                                   onToggleLine: lineToggle,
                                   headerControls: { headerControls(for: $0) },
                                   gaps: gaps, expandedGaps: expandedGaps, fileLines: fileLines ?? [],
                                   onExpandGap: { expandedGaps.insert($0) })
            case .split:
                DiffSplitContent(hunks: hunks, highlighted: highlighted,
                                 headerControls: { headerControls(for: $0) },
                                 gaps: gaps, expandedGaps: expandedGaps, fileLines: fileLines ?? [],
                                 onExpandGap: { expandedGaps.insert($0) })
            }
        }
    }

    /// Re-tokenises when the file, its hunks or the light/dark syntax
    /// palette change — everything the cached attributed strings depend on.
    /// Uses the effective mode so following the system appearance re-colours.
    private var tokenizeKey: String {
        "\(file ?? "")|\(hunks.map { "\($0.id):\($0.lines.count)" }.joined(separator: ","))|\(theme.effectiveMode.rawValue)"
    }

    // MARK: Hidden lines

    private var gaps: [DiffGap] {
        guard let fileLines else { return [] }
        return DiffGaps.gaps(in: hunks, newLineCount: fileLines.count)
    }

    /// Fresh for every diff: the gaps and their ids belong to these hunks.
    private func loadFileLines() async {
        expandedGaps = []
        fileLines = nil
        guard let loadNewSide, !loading, !hunks.isEmpty else { return }
        let lines = await loadNewSide()
        if Task.isCancelled { return }
        fileLines = lines
    }

    // MARK: Hunk actions

    private var selectionKey: String {
        "\(file ?? "")|\(hunks.map { "\($0.id):\($0.oldStart):\($0.lines.count)" }.joined(separator: ","))"
    }

    private var lineToggle: ((DiffHunk, DiffLine) -> Void)? {
        guard hunkActions != nil else { return nil }
        return { hunk, line in toggle(line, in: hunk) }
    }

    private func toggle(_ line: DiffLine, in hunk: DiffHunk) {
        var picked = selectedLines[hunk.id] ?? []
        if picked.contains(line.id) { picked.remove(line.id) } else { picked.insert(line.id) }
        selectedLines[hunk.id] = picked.isEmpty ? nil : picked
    }

    /// Buttons for one hunk, titled for its picked lines: "Stage hunk" with
    /// none, "Stage 2 lines" with some. Only unified view picks lines.
    private func headerControls(for hunk: DiffHunk) -> DiffHunkHeader.Controls? {
        guard let actions = hunkActions else { return nil }
        let picked = viewMode == .unified ? selectedLines[hunk.id] : nil
        let target = picked.map { $0.count == 1 ? "1 line" : "\($0.count) lines" } ?? "hunk"
        var controls = DiffHunkHeader.Controls(
            applyTitle: "\(actions.verb) \(target)",
            onApply: { actions.onApply(hunk, picked) },
            disabled: actions.disabled
        )
        if actions.onDiscard != nil {
            controls.discardTitle = "Discard \(target)…"
            controls.onDiscard = { pendingDiscard = PendingDiscard(hunk: hunk, lineIds: picked) }
        }
        return controls
    }

    private var discardBinding: Binding<Bool> {
        Binding(get: { pendingDiscard != nil }, set: { if !$0 { pendingDiscard = nil } })
    }

    private var discardTitle: String {
        guard let pending = pendingDiscard else { return "" }
        if let ids = pending.lineIds { return ids.count == 1 ? "Discard 1 line?" : "Discard \(ids.count) lines?" }
        return "Discard this hunk?"
    }

    /// Above this many lines the diff renders as plain text: tokenising runs
    /// highlight.js in JavaScriptCore hunk by hunk, and a generated file or a
    /// lockfile could keep it busy for seconds while holding every
    /// attributed line in memory.
    static let highlightLineLimit = 5_000
    /// Highlighting is published in batches of roughly this many lines so the
    /// first hunks colour in right away instead of after the whole file.
    private static let highlightBatchLines = 300

    private func tokenizeHunks() async {
        highlighted = [:]
        guard let language = DiffSyntaxHighlighter.languageId(for: file),
              !hunks.isEmpty,
              hunks.reduce(0, { $0 + $1.lines.count }) <= Self.highlightLineLimit else {
            return
        }
        let css = DiffSyntaxHighlighter.css(for: SyntaxPalette.make(theme.variant))
        let themeId = theme.effectiveMode.rawValue
        var output: [Int: [Int: AttributedString]] = [:]
        var unpublishedLines = 0
        for hunk in hunks {
            let lines = await DiffSyntaxHighlighter.shared.tokenize(
                hunk: hunk,
                language: language,
                css: css,
                themeId: themeId
            )
            if Task.isCancelled { return }
            if !lines.isEmpty { output[hunk.id] = lines }
            unpublishedLines += hunk.lines.count
            if unpublishedLines >= Self.highlightBatchLines {
                highlighted = output
                unpublishedLines = 0
            }
        }
        highlighted = output
    }
}

/// What the diff pane offers per hunk in Changes: stage (unstaged side) or
/// unstage (staged side), and discard on the unstaged side. The closures
/// get the hunk and the picked line ids (`nil`: the whole hunk).
struct DiffHunkActions {
    /// "Stage" or "Unstage".
    let verb: String
    let onApply: (DiffHunk, Set<Int>?) -> Void
    var onDiscard: ((DiffHunk, Set<Int>?) -> Void)? = nil
    var disabled = false
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .unified
    DiffPane(
        file: "src/components/CommitGraph.tsx",
        status: .modified,
        hunks: DiffHunk.previewSamples,
        viewMode: $mode
    )
    .frame(width: 720, height: 320)
    .appTheme(theme)
}

#Preview("Split") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var mode: DiffPane.ViewMode = .split
    DiffPane(
        file: "src/components/CommitGraph.tsx",
        status: .modified,
        hunks: DiffHunk.previewSamples,
        viewMode: $mode
    )
    .frame(width: 720, height: 320)
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
    .appTheme(theme)
}
