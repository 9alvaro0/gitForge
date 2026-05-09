import SwiftUI

struct StashOverviewTab: View {
    let detail: StashDetail?

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxl) {
                if let detail {
                    metaBlock(detail)
                    subjectBlock(detail.stash)
                } else {
                    placeholder.skeleton(true)
                }
            }
            .padding(DesignTokens.Spacing.xxxxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func metaBlock(_ detail: StashDetail) -> some View {
        block {
            row(label: "Reference", value: detail.stash.reference)
            row(label: "Branch",    value: detail.parentBranch ?? "—")
            row(label: "Parent",    value: String(detail.parentSha.prefix(7)))
            row(label: "Stashed",   value: detail.authorDate.map { theme.dateDisplayMode.format($0) } ?? "—")
            row(label: "Files",     value: "\(detail.files.count) changed")
        }
    }

    private func subjectBlock(_ stash: Stash) -> some View {
        block(spacing: DesignTokens.Spacing.sm) {
            Text("MESSAGE")
                .font(.system(size: FontSize.caption, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(theme.palette.fg3)
            Text(stash.subject)
                .font(AppFont.sans(12.5))
                .foregroundStyle(theme.palette.fg1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var placeholder: some View {
        block {
            row(label: "Reference", value: "stash@{0}")
            row(label: "Branch",    value: "main")
            row(label: "Parent",    value: "abc1234")
            row(label: "Stashed",   value: "2 hours ago")
            row(label: "Files",     value: "3 changed")
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Text(label.uppercased())
                .font(.system(size: FontSize.caption, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(theme.palette.fg3)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(AppFont.mono(12, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
            Spacer()
        }
    }

    @ViewBuilder
    private func block<Content: View>(spacing: CGFloat = DesignTokens.Spacing.sm,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    StashOverviewTab(detail: .previewSample)
        .frame(width: 1100, height: 600)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
