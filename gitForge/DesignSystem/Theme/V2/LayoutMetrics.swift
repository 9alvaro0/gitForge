import CoreGraphics

/// Fixed screen measures that aren't part of the density scale.
nonisolated enum LayoutMetrics {
    /// Keyboard / VoiceOver resize increment for the drag handles.
    static let resizeStep: CGFloat = 20
    /// Height of the repository row at the top of the sidebar.
    static let sidebarRepoRow: CGFloat = 38
    /// Width of a drill-in detail column (uncommitted changes, stash).
    static let detailPanelWidth: CGFloat = 360
    /// Height of a plain control row (skeleton toolbar placeholders).
    static let controlHeight: CGFloat = 28
}
