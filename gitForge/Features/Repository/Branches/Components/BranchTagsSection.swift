import SwiftUI

/// "Tags" section under the Branches view — wraps a `FlowLayout` of
/// `BranchTagPill`s with a header label.
struct BranchTagsSection: View {
    let tags: [GitRef]
    let onPush: (GitRef) -> Void
    let onDelete: (GitRef) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("TAGS")
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            FlowLayout(spacing: DesignTokens.Spacing.sm) {
                ForEach(tags) { tag in
                    BranchTagPill(tag: tag, onPush: onPush, onDelete: onDelete)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let tags: [GitRef] = (1...8).map { i in
        GitRef(name: "v1.\(i).0", kind: .tag, targetSha: "sha\(i)", isHead: false)
    }
    return BranchTagsSection(tags: tags, onPush: { _ in }, onDelete: { _ in })
        .frame(width: 760)
        .padding()
        .background(theme.palette.bg2)
        .appTheme(theme)
}
