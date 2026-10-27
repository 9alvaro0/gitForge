import SwiftUI

/// History's right pane: the selected commit's (or the working copy's)
/// detail over the selected file's diff. Owns the diff's height and collapsed
/// flag (both persisted), so dragging that divider re-renders only this pane.
struct HistoryInspector: View {
    @Bindable var viewModel: RepositoryViewModel
    let isUncommittedSelected: Bool
    let diffMode: Binding<DiffPane.ViewMode>
    /// Hides the whole inspector.
    let onClose: () -> Void
    let onExpandDiff: () -> Void

    @Environment(\.appTheme) private var theme

    @State private var diffHeight = HistoryInspectorMetrics.storedDiffHeight()
    @State private var diffCollapsed = UserDefaults.standard.bool(forKey: HistoryInspectorMetrics.collapsedKey)

    var body: some View {
        GeometryReader { geo in
            let cap = HistoryInspectorMetrics.diffHeightCap(available: geo.size.height)
            VStack(spacing: 0) {
                detailContent
                    .frame(maxHeight: .infinity)
                if hasSelection {
                    if diffCollapsed {
                        CollapsedPaneStrip(kind: .diff) { setDiffCollapsed(false) }
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
                            onCommit: {
                                UserDefaults.standard.set(Double(diffHeight), forKey: HistoryInspectorMetrics.heightKey)
                            }
                        )
                        HistoryDiffPane(
                            viewModel: viewModel,
                            isUncommittedSelected: isUncommittedSelected,
                            diffMode: diffMode,
                            onClose: { setDiffCollapsed(true) },
                            onToggleExpand: onExpandDiff
                        )
                        .frame(height: min(diffHeight, cap))
                    }
                }
            }
        }
        .background(theme.colors.bgElevated)
        // A new selection shows its diff, unless the user hid the pane.
        .onChange(of: selectionKey) { revealDiff() }
    }

    private var hasSelection: Bool {
        isUncommittedSelected || viewModel.history.selectedCommit != nil
    }

    private var selectionKey: String? {
        isUncommittedSelected ? "" : viewModel.history.selectedCommitId
    }

    @ViewBuilder
    private var detailContent: some View {
        if isUncommittedSelected {
            ScrollView {
                UncommittedDetailColumn(viewModel: viewModel, onClose: onClose)
                    .padding(Spacing.s16)
            }
        } else if let commit = viewModel.history.selectedCommit {
            ScrollView {
                CommitDetailColumn(commit: commit, viewModel: viewModel, onClose: onClose)
                    .padding(Spacing.s16)
            }
        } else {
            EmptyState(symbol: "clock.arrow.circlepath", title: String(localized: "Select a commit"),
                       subtitle: String(localized: "Its detail and changes appear here.")) { EmptyView() }
                .overlay(alignment: .topTrailing) {
                    IconButton(symbol: "xmark", accessibilityLabel: String(localized: "Hide commit detail"),
                               action: onClose)
                        .help("Hide commit detail")
                        .padding(Spacing.s8)
                }
        }
    }

    /// A pane dragged down to a sliver grows back to the default height so
    /// the new selection's diff is readable. A hidden pane stays hidden: the
    /// user closed it on purpose.
    private func revealDiff() {
        guard hasSelection, !diffCollapsed else { return }
        let revealed = HistoryInspectorMetrics.revealedDiffHeight(current: diffHeight)
        guard revealed != diffHeight else { return }
        withAnimation(Motion.standard) { diffHeight = revealed }
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
    static let minDiffHeight: CGFloat = 36
    /// Below this the pane is a sliver: a new selection grows it back.
    static let sliverHeight: CGFloat = 80
    /// What the detail above keeps when the diff is as tall as it can be.
    static let minDetailHeight: CGFloat = 120
    /// The divider between detail and diff (`RowDragHandle`).
    static let handleHeight: CGFloat = 8

    /// Tallest the diff may be in an inspector `available` points tall.
    static func diffHeightCap(available: CGFloat) -> CGFloat {
        max(minDiffHeight, available - handleHeight - minDetailHeight)
    }

    /// A sliver shorter than `threshold` bumps up to `defaultHeight`;
    /// anything taller stays put.
    static func revealedDiffHeight(current: CGFloat, threshold: CGFloat = sliverHeight,
                                   defaultHeight: CGFloat = defaultDiffHeight) -> CGFloat {
        current < threshold ? defaultHeight : current
    }

    static func storedDiffHeight(_ defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.double(forKey: heightKey)
        return stored > 0 ? CGFloat(stored) : defaultDiffHeight
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
    HistoryInspector(viewModel: vm, isUncommittedSelected: false, diffMode: $mode,
                     onClose: {}, onExpandDiff: {})
        .previewAppState(.preview)
        .frame(width: 480, height: 720)
        .appTheme(theme)
}
