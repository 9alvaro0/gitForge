import SwiftUI

/// History's right pane: the selected commit's (or the working copy's)
/// detail over the selected file's diff. Owns the diff's height and collapsed
/// flag (both persisted), so dragging that divider re-renders only this pane.
/// The detail keeps its header in place and scrolls its file list on its own
/// (`CommitDetailColumn`, `UncommittedDetailColumn`), so the diff can take
/// height without pushing anything out of reach.
struct HistoryInspector: View {
    @Bindable var viewModel: RepositoryViewModel
    let isUncommittedSelected: Bool
    let diffMode: Binding<DiffPane.ViewMode>
    let onExpandDiff: () -> Void

    @Environment(\.appTheme) private var theme

    @State private var diffHeight = HistoryInspectorMetrics.storedDiffHeight()
    @State private var diffCollapsed = UserDefaults.standard.bool(forKey: HistoryInspectorMetrics.collapsedKey)
    /// The divider is dragged past the diff's collapse point: the pane gets
    /// out of the way, and collapses for good if released there.
    @State private var collapsePending = false

    var body: some View {
        GeometryReader { geo in
            let cap = HistoryInspectorMetrics.diffHeightCap(available: geo.size.height)
            VStack(spacing: 0) {
                detailContent
                    .frame(maxHeight: .infinity)
                if hasSelection {
                    if diffCollapsed {
                        CollapsedPaneStrip { setDiffCollapsed(false) }
                    } else {
                        RowDragHandle(
                            // Like the inspector's width: shown and stored
                            // within the room left, so the pane never pushes
                            // the detail out or the column past the window.
                            height: Binding(
                                get: { min(diffHeight, cap) },
                                set: { diffHeight = min($0, cap) }
                            ),
                            minHeight: HistoryInspectorMetrics.minDiffHeight,
                            maxHeight: cap,
                            collapseBelow: PaneResize.collapseThreshold(min: HistoryInspectorMetrics.minDiffHeight),
                            onCollapsingChange: { collapsePending = $0 },
                            onCommit: commitDrag
                        )
                        HistoryDiffPane(
                            viewModel: viewModel,
                            isUncommittedSelected: isUncommittedSelected,
                            diffMode: diffMode,
                            onClose: { setDiffCollapsed(true) },
                            onToggleExpand: onExpandDiff
                        )
                        .frame(height: collapsePending ? 0 : min(diffHeight, cap))
                        .opacity(collapsePending ? 0 : 1)
                        .allowsHitTesting(!collapsePending)
                        .clipped()
                    }
                }
            }
        }
        .background(theme.colors.bgElevated)
    }

    private var hasSelection: Bool {
        isUncommittedSelected || viewModel.history.selectedCommit != nil
    }

    @ViewBuilder
    private var detailContent: some View {
        if isUncommittedSelected {
            UncommittedDetailColumn(viewModel: viewModel)
        } else if let commit = viewModel.history.selectedCommit {
            CommitDetailColumn(commit: commit, viewModel: viewModel)
        } else {
            EmptyState(symbol: "clock.arrow.circlepath", title: String(localized: "Select a commit"),
                       subtitle: String(localized: "Its detail and changes appear here.")) { EmptyView() }
        }
    }

    private func commitDrag() {
        UserDefaults.standard.set(Double(diffHeight), forKey: HistoryInspectorMetrics.heightKey)
        guard collapsePending else { return }
        collapsePending = false
        setDiffCollapsed(true)
    }

    private func setDiffCollapsed(_ value: Bool) {
        withAnimation(Motion.standard) { diffCollapsed = value }
        UserDefaults.standard.set(value, forKey: HistoryInspectorMetrics.collapsedKey)
    }
}

/// Sizes and persisted keys of `HistoryInspector`'s diff.
nonisolated enum HistoryInspectorMetrics {
    static let heightKey = "gitForge.history.diffPaneHeight"
    static let collapsedKey = "gitForge.history.diffPaneCollapsed"
    static let defaultDiffHeight: CGFloat = 340
    /// The diff's header and a few lines. Dragged under half of it, the pane
    /// collapses (audit B3), so it is never a sliver.
    static let minDiffHeight: CGFloat = 96
    /// What the detail above keeps when the diff is as tall as it can be:
    /// its header, a couple of lines of unfolded details and a couple of
    /// files (`minDetailsScrollHeight`, `minFileListHeight`).
    static let minDetailHeight: CGFloat = 248
    /// Unfolded details squeezed by a tall diff still show this much.
    static let minDetailsScrollHeight: CGFloat = 40
    /// The changed files squeezed by a tall diff still show this much.
    static let minFileListHeight: CGFloat = 52
    /// The divider between detail and diff (`RowDragHandle`).
    static let handleHeight: CGFloat = 8
    /// The commit's details (parents, signature, message) are unfolded.
    static let detailsExpandedKey = "gitForge.history.inspectorDetailsExpanded"
    /// Share of the commit detail its unfolded details may take before they
    /// scroll, so a long message never pushes the files out.
    static let detailsShare: CGFloat = 0.4
    static let minDetailsHeight: CGFloat = 72

    /// Tallest the unfolded details may be in a commit detail
    /// `columnHeight` points tall.
    static func detailsCap(columnHeight: CGFloat) -> CGFloat {
        max(minDetailsHeight, columnHeight * detailsShare)
    }

    /// Tallest the diff may be in an inspector `available` points tall.
    static func diffHeightCap(available: CGFloat) -> CGFloat {
        max(minDiffHeight, available - handleHeight - minDetailHeight)
    }

    /// The saved height, or the default; never under the minimum (a height
    /// saved when the minimum was a sliver comes back readable).
    static func storedDiffHeight(_ defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.double(forKey: heightKey)
        return stored > 0 ? max(minDiffHeight, CGFloat(stored)) : defaultDiffHeight
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
    HistoryInspector(viewModel: vm, isUncommittedSelected: false, diffMode: $mode, onExpandDiff: {})
        .previewAppState(.preview)
        .frame(width: 480, height: 720)
        .appTheme(theme)
}
