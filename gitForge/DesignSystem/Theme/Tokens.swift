import SwiftUI

/// Geometry & misc design constants used across the redesigned UI.
enum DesignTokens {
    /// Generic spacing scale — paddings, stack `spacing:`, small frame dimensions.
    /// Prefer these over raw numbers so the whole app moves together when the
    /// scale shifts. `Density.pad` still wins where the value should respond
    /// to the user's density preference.
    enum Spacing {
        static let none: CGFloat = 0
        static let hairline: CGFloat = 1
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 14
        static let xxxl: CGFloat = 16
        static let xxxxl: CGFloat = 18
        static let huge: CGFloat = 20
        static let xhuge: CGFloat = 24
        static let xxhuge: CGFloat = 32
        static let xxxhuge: CGFloat = 40
    }

    enum Radius {
        static let xs: CGFloat = 3
        static let sm: CGFloat = 5
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        /// Chip / drag-indicator corner — slightly chunkier than `lg`.
        static let chip: CGFloat = 10
        static let xl: CGFloat = 12
        static let pill: CGFloat = 999
    }

    /// Border / divider widths.
    enum Stroke {
        static let regular: CGFloat = 1
        static let thick: CGFloat = 2
    }

    /// Inline icon sizes for `Image.frame(width:height:)` / `.font(.system(size:))`.
    enum IconSize {
        static let xs: CGFloat = 10
        static let sm: CGFloat = 12
        static let md: CGFloat = 14
        static let lg: CGFloat = 16
        static let xl: CGFloat = 18
        static let xxl: CGFloat = 24
    }

    /// Curated opacities for overlays, dividers, dimmed states.
    enum Opacity {
        static let faint: Double = 0.06
        static let subtle: Double = 0.10
        static let muted: Double = 0.14
        static let strong: Double = 0.22
        static let dim: Double = 0.30
        static let prominent: Double = 0.85
    }

    /// Animation presets so timings stay coherent across the app.
    enum Motion {
        static let fast: Animation = .easeOut(duration: 0.12)
        static let standard: Animation = .easeOut(duration: 0.18)
        static let slow: Animation = .easeInOut(duration: 0.9)

        static let fastDuration: TimeInterval = 0.12
        static let standardDuration: TimeInterval = 0.18
        static let slowDuration: TimeInterval = 0.9
    }

    enum Sidebar {
        static let width: CGFloat = 256
        static let searchHeight: CGFloat = 30
        static let repoRow: CGFloat = 38
        static let navRow: CGFloat = 28
    }

    enum Window {
        static let titlebarHeight: CGFloat = 36
        static let statusbarHeight: CGFloat = 26
        static let chromeRadius: CGFloat = 12
    }

    enum Detail {
        static let panelWidth: CGFloat = 360
        static let diffPaneHeight: CGFloat = 280
    }

    enum Conflict {
        static let filesWidth: CGFloat = 280
    }

    enum Pulls {
        static let listWidth: CGFloat = 380
    }

    enum Staging {
        static let filesWidth: CGFloat = 380
    }
}
