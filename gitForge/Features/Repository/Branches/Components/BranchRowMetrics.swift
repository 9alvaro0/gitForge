import Foundation
import CoreGraphics

/// Shared sizing for the branch list rows so the folder header, the leaf row
/// and the column-header line up exactly. Tweak in one place if the table
/// columns change width.
enum BranchRowMetrics {
    /// Width reserved on the right of the row for `Checkout` + overflow menu.
    static let actionsColumn: CGFloat = 130
    /// Width reserved for the "last commit" timestamp column.
    static let lastCommitColumn: CGFloat = 200
    /// Indentation step per tree depth.
    static let indentStep: CGFloat = 16
    /// Leading inset before the depth indentation kicks in (room for the
    /// HEAD indicator dot).
    static let leadingInset: CGFloat = 14

    static func indent(depth: Int) -> CGFloat {
        CGFloat(depth) * indentStep + leadingInset
    }
}
