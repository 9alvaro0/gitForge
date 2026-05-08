import SwiftUI

/// `.gf-content-h` — title + subtitle on the left, action cluster on the right.
struct ContentHeader<Subtitle: View, Right: View>: View {
    let title: String
    @ViewBuilder var subtitle: () -> Subtitle
    @ViewBuilder var right: () -> Right

    @Environment(\.appTheme) private var theme

    init(title: String,
         @ViewBuilder subtitle: @escaping () -> Subtitle = { EmptyView() },
         @ViewBuilder right: @escaping () -> Right = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.right = right
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxxl) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xl) {
                Text(title)
                    .font(AppFont.sans(18, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
                subtitle()
                    .foregroundStyle(theme.palette.fg3)
                    .font(AppFont.sans(12))
            }
            Spacer(minLength: 0)
            HStack(spacing: DesignTokens.Spacing.sm) {
                right()
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .padding(.vertical, DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.lineStrong).frame(height: 1)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: DesignTokens.Spacing.none) {
        ContentHeader(title: "History") {
            MonoText("main · 247 commits", dim: true)
        } right: {
            ToolButton(.fetch, label: "Fetch") { }
            ToolButton(.pull, label: "Pull", badge: 1) { }
            ToolButton(.push, label: "Push", badge: 7, primary: true) { }
        }
        Spacer()
    }
    .frame(height: 200)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
