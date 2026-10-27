import SwiftUI

/// History's two panes: the commit table and, on its right, the inspector,
/// split by a draggable divider. Owns the inspector's width (persisted), so
/// dragging the divider re-renders this layout and the panes, not
/// `HistoryView` with its search and focus.
///
/// The inspector shows and hides with the toolbar button and View › Show
/// Inspector (⌃⌘I), which `HistoryView` wires to `isInspectorVisible`. Like
/// `NSSplitView`, a double-click on the divider or dragging it past half the
/// inspector's minimum hides it too. (A native `.inspector` was tried and
/// dropped: see the audit, finding M2.)
struct HistorySplitLayout<Table: View, Inspector: View>: View {
    let table: Table
    @Binding var isInspectorVisible: Bool
    @ViewBuilder let inspector: () -> Inspector

    @Environment(\.appTheme) private var theme

    @State private var inspectorWidth = HistorySplitMetrics.storedInspectorWidth()
    /// The divider is dragged past the inspector's collapse point: the pane
    /// gets out of the way, and hides for good if released there.
    @State private var collapsePending = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                table
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isInspectorVisible {
                    let cap = HistorySplitMetrics.inspectorCap(available: geo.size.width)
                    ColumnDragHandle(
                        // Reads and writes the width actually shown, so a
                        // drag past the cap can't bank invisible width.
                        width: Binding(
                            get: { min(inspectorWidth, cap) },
                            set: { inspectorWidth = min($0, cap) }
                        ),
                        minWidth: HistorySplitMetrics.minInspectorWidth,
                        maxWidth: cap,
                        inverted: true,
                        dividerColor: theme.colors.separator,
                        onCommit: commitDrag,
                        onDoubleClick: hide,
                        doubleClickActionName: String(localized: "Hide Inspector"),
                        collapseBelow: PaneResize.collapseThreshold(min: HistorySplitMetrics.minInspectorWidth),
                        onCollapsingChange: { collapsePending = $0 }
                    )
                    inspector()
                        .frame(width: collapsePending ? 0 : min(inspectorWidth, cap))
                        .opacity(collapsePending ? 0 : 1)
                        .allowsHitTesting(!collapsePending)
                        .clipped()
                        .transition(.move(edge: .trailing))
                }
            }
        }
    }

    private func commitDrag() {
        UserDefaults.standard.set(Double(inspectorWidth), forKey: HistorySplitMetrics.widthKey)
        guard collapsePending else { return }
        collapsePending = false
        hide()
    }

    private func hide() {
        withAnimation(Motion.standard) { isInspectorVisible = false }
    }
}

/// Sizes and persisted keys of `HistorySplitLayout`.
nonisolated enum HistorySplitMetrics {
    static let widthKey = "gitForge.history.detailPanelWidth"
    /// Stores whether the inspector is hidden (its name predates the toolbar
    /// button), so a choice made before carries over.
    static let collapsedKey = "gitForge.history.detailPanelCollapsed"
    static let minInspectorWidth: CGFloat = 320
    /// Spec §4.6: inspector 480; the table keeps at least `minTableWidth`.
    static let defaultInspectorWidth: CGFloat = 480
    static let minTableWidth: CGFloat = 520
    /// The divider between the panes (`ColumnDragHandle`).
    static let handleWidth: CGFloat = 8

    /// Widest the inspector may be: whatever leaves the table its
    /// `minTableWidth` (the handle's own width included), never under the
    /// inspector's own minimum (audit B2).
    static func inspectorCap(available: CGFloat) -> CGFloat {
        max(minInspectorWidth, available - minTableWidth - handleWidth)
    }

    /// The saved width, or the default. Not capped here: the window it was
    /// saved in may have been wider, and `inspectorCap` applies when shown.
    static func storedInspectorWidth(_ defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.double(forKey: widthKey)
        let resolved = stored > 0 ? CGFloat(stored) : defaultInspectorWidth
        return max(minInspectorWidth, resolved)
    }

    static func storedInspectorVisible(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: collapsedKey)
    }

    static func storeInspectorVisible(_ visible: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(!visible, forKey: collapsedKey)
    }
}
