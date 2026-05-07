import SwiftUI

/// Geometry & misc design constants used across the redesigned UI.
enum DesignTokens {
    enum Radius {
        static let xs: CGFloat = 3
        static let sm: CGFloat = 5
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 12
        static let pill: CGFloat = 999
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
