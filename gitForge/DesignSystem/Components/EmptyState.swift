import SwiftUI

/// Centered placeholder: icon tile, title, subtitle, one secondary action
/// (redesign spec §5).
struct EmptyState<Action: View>: View {
    /// SF Symbol name.
    let symbol: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var action: () -> Action

    @Environment(\.appTheme) private var theme

    init(symbol: String,
         title: String,
         subtitle: String? = nil,
         @ViewBuilder action: @escaping () -> Action = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.s8) {
            Image(systemName: symbol)
                .font(.system(size: 24 * 0.8, weight: .medium))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
                .background(RoundedRectangle(cornerRadius: Radius.popover).fill(theme.colors.fillControl))
                .padding(.bottom, Spacing.s4)
            Text(title)
                .textRole(.headline)
                .foregroundStyle(theme.colors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            action()
                .padding(.top, Spacing.s4)
        }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s32)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    EmptyState(symbol: "arrow.triangle.pull", title: "No pull requests open",
               subtitle: "When you open a PR it'll show up here.") {
        GFButton(title: "New PR", style: .primary) { }
    }
    .frame(width: 480, height: 320)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
