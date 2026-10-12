import CoreGraphics

/// Fixed screen measures that aren't part of the density scale.
nonisolated enum LayoutMetrics {
    /// Keyboard / VoiceOver resize increment for the drag handles.
    static let resizeStep: CGFloat = 20
    /// Height of the repository row at the top of the sidebar: name (body)
    /// and branch (monoSmall) lines plus 6 above and below.
    static let sidebarRepoRow: CGFloat = 44
    /// Row height of the History loading skeleton.
    static let controlHeight: CGFloat = 28

    /// Onboarding content: space above the step's counter.
    static let onboardingTop: CGFloat = 72
    /// Onboarding content's side margin on a wide column (artboard), and
    /// the column width from which it applies; narrower keeps `Spacing.s48`
    /// so the Appearance step's preview still fits beside its controls.
    static let onboardingGutterWide: CGFloat = 96
    static let onboardingWideColumn: CGFloat = 1000

    static func onboardingGutter(columnWidth: CGFloat) -> CGFloat {
        columnWidth >= onboardingWideColumn ? onboardingGutterWide : Spacing.s48
    }
}
