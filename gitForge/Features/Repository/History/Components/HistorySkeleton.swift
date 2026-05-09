import SwiftUI

/// First-fetch placeholder rows for the History table. Realistic-looking
/// commit subjects keep the layout grounded so the skeleton reads as
/// "loading commits", not as a blank pane.
struct HistorySkeleton: View {
    @Environment(\.appTheme) private var theme

    private static let placeholderSubjects = [
        "feat: add merge request integration",
        "fix: handle nil reviewer avatar URLs",
        "refactor: split provider-specific mappers",
        "chore: bump dependency versions",
        "feat: skeleton loaders for first-fetch states",
        "test: cover empty merge request payloads",
        "fix: history scroll jumps on selection",
        "feat: graph perf improvements",
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.none) {
                ForEach(0..<10, id: \.self) { index in
                    row(index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.bg2)
        .skeleton(true)
    }

    @ViewBuilder
    private func row(index: Int) -> some View {
        let subject = Self.placeholderSubjects[index % Self.placeholderSubjects.count]
        HStack(spacing: DesignTokens.Spacing.xl) {
            Text("main")
                .font(AppFont.mono(11, family: theme.monoFont))
                .padding(.horizontal, DesignTokens.Spacing.sm).padding(.vertical, DesignTokens.Spacing.hairline)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg3))
                .frame(width: 100, alignment: .leading)
            Text(subject)
                .font(AppFont.sans(12.5))
                .foregroundStyle(theme.palette.fg1)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("9alvaro0")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: 110, alignment: .leading)
            Text("abc1234")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.accent)
                .frame(width: 70, alignment: .leading)
            Text("2h")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: 50, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(height: DesignTokens.Control.height)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
    }
}

/// Capsule shown over the table while the next page of commits is loading.
struct LoadingMoreFooter: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ProgressView().controlSize(.small).scaleEffect(0.7)
            Text("Loading more commits…")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
        .padding(.bottom, DesignTokens.Spacing.xl)
    }
}

#Preview("Skeleton") {
    @Previewable @State var theme = AppTheme()
    HistorySkeleton()
        .frame(width: 760, height: 480)
        .appTheme(theme)
}

#Preview("Loading more") {
    @Previewable @State var theme = AppTheme()
    LoadingMoreFooter()
        .padding()
        .background(theme.palette.bg2)
        .appTheme(theme)
}
