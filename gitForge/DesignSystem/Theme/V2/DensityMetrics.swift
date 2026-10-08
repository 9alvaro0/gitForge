import CoreGraphics

/// Row heights and fixed widths per density (redesign spec §4.6).
nonisolated struct DensityMetrics: Equatable, Sendable {
    let rowList: CGFloat
    let rowSidebar: CGFloat
    let rowBranch: CGFloat
    let rowFile: CGFloat
    let rowHeader: CGFloat
    let diffLine: CGFloat
    let toolbarControl: CGFloat
    let toolbarInner: CGFloat
    let buttonRegular: CGFloat
    let buttonLarge: CGFloat
    let buttonSmall: CGFloat
    let fieldHeight: CGFloat
    let sidebarWidth: CGFloat
    let inspectorWidth: CGFloat
    let graph: GraphMetrics

    static let regular = DensityMetrics(
        rowList: 28, rowSidebar: 28, rowBranch: 26, rowFile: 24, rowHeader: 28, diffLine: 19,
        toolbarControl: 34, toolbarInner: 28, buttonRegular: 28, buttonLarge: 32, buttonSmall: 22,
        fieldHeight: 32, sidebarWidth: 240, inspectorWidth: 480, graph: .regular
    )

    static let compact = DensityMetrics(
        rowList: 22, rowSidebar: 24, rowBranch: 22, rowFile: 20, rowHeader: 24, diffLine: 17,
        toolbarControl: 34, toolbarInner: 28, buttonRegular: 24, buttonLarge: 32, buttonSmall: 22,
        fieldHeight: 28, sidebarWidth: 240, inspectorWidth: 480, graph: .compact
    )
}
