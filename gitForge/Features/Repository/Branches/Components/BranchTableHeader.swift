import SwiftUI

/// Column titles above the Branches & Tags table, aligned with `BranchRow`.
struct BranchTableHeader: View {
    let scope: BranchScope
    let layout: BranchTableLayout

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Text(scope == .tags ? "Tag" : "Branch")
                .frame(maxWidth: .infinity, alignment: .leading)
            if layout.upstream > 0 {
                Text("vs upstream").frame(width: layout.upstream, alignment: .leading)
            }
            if layout.commit > 0 {
                Text("Commit").frame(width: layout.commit, alignment: .leading)
            }
            if layout.subject > 0 {
                Text("Last commit").frame(width: layout.subject, alignment: .leading)
            }
            Text("Updated").frame(width: layout.updated, alignment: .trailing)
        }
        .textRole(.caption, weight: .semibold)
        .foregroundStyle(theme.colors.textQuaternary)
        .lineLimit(1)
        .padding(.horizontal, Spacing.s12 + Spacing.s6)
        .frame(height: theme.density.metrics.rowHeader)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
    }
}
