import SwiftUI

/// History's two panes: the commit table and, on its right, the inspector,
/// split by a draggable divider. Owns the inspector's width and collapsed
/// flag (both persisted), so dragging the divider re-renders this layout and
/// the panes, not `HistoryView` with its search and focus.
struct HistorySplitLayout<Table: View, Inspector: View>: View {
    let table: Table
    /// Gets the action that collapses the inspector, for its close button.
    @ViewBuilder let inspector: (_ collapse: @escaping () -> Void) -> Inspector

    @Environment(\.appTheme) private var theme

    @State private var inspectorWidth = HistorySplitMetrics.storedInspectorWidth()
    @State private var collapsed = UserDefaults.standard.bool(forKey: HistorySplitMetrics.collapsedKey)

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                table
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if collapsed {
                    CollapsedPaneStrip(kind: .detail) { setCollapsed(false) }
                } else {
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
                        onCommit: {
                            UserDefaults.standard.set(Double(inspectorWidth), forKey: HistorySplitMetrics.widthKey)
                        },
                        onDoubleClick: { setCollapsed(true) },
                        doubleClickActionName: String(localized: "Hide commit detail")
                    )
                    inspector { setCollapsed(true) }
                        .frame(width: min(inspectorWidth, cap))
                }
            }
        }
    }

    private func setCollapsed(_ value: Bool) {
        withAnimation(Motion.standard) { collapsed = value }
        UserDefaults.standard.set(value, forKey: HistorySplitMetrics.collapsedKey)
    }
}

/// Sizes and persisted keys of `HistorySplitLayout`.
nonisolated enum HistorySplitMetrics {
    static let widthKey = "gitForge.history.detailPanelWidth"
    static let collapsedKey = "gitForge.history.detailPanelCollapsed"
    static let minInspectorWidth: CGFloat = 320
    static let maxInspectorWidth: CGFloat = 760
    /// Spec §4.6: inspector 480; the table keeps at least `minTableWidth`.
    static let defaultInspectorWidth: CGFloat = 480
    static let minTableWidth: CGFloat = 520
    /// The divider between the panes (`ColumnDragHandle`).
    static let handleWidth: CGFloat = 8

    /// Widest the inspector may be so the table keeps `minTableWidth`
    /// (the handle's own width included).
    static func inspectorCap(available: CGFloat) -> CGFloat {
        min(maxInspectorWidth, max(minInspectorWidth, available - minTableWidth - handleWidth))
    }

    static func storedInspectorWidth(_ defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.double(forKey: widthKey)
        let resolved = stored > 0 ? CGFloat(stored) : defaultInspectorWidth
        return min(max(minInspectorWidth, resolved), maxInspectorWidth)
    }
}
