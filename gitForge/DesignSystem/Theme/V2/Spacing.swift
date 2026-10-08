import CoreGraphics

/// v2 spacing scale in points (redesign spec §4.3). Replaces
/// `DesignTokens.Spacing` in phase F9.
nonisolated enum Spacing {
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s6: CGFloat = 6
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48
}

/// v2 corner radii (redesign spec §4.4). Capsules use `Capsule()`.
/// Replaces `DesignTokens.Radius` in phase F9.
nonisolated enum Radius {
    /// A/M/D badges, kbd.
    static let badge: CGFloat = 4
    /// Ref chips.
    static let chip: CGFloat = 5
    /// Small buttons and inline segments.
    static let controlSmall: CGFloat = 6
    /// List row selection.
    static let row: CGFloat = 7
    /// Buttons, fields.
    static let control: CGFloat = 8
    /// Cards, repo tile, content pane corner.
    static let card: CGFloat = 12
    /// HUDs, popovers, toasts.
    static let popover: CGFloat = 14
    /// Glass sidebar, command palette.
    static let panel: CGFloat = 18
}
