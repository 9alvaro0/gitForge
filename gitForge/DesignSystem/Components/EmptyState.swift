import SwiftUI

/// Centered placeholder: icon tile, title, subtitle, one secondary action
/// (redesign spec §5).
struct EmptyState<Action: View>: View {
    let icon: GFIconKind
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var action: () -> Action

    @Environment(\.appTheme) private var theme

    init(icon: GFIconKind,
         title: String,
         subtitle: String? = nil,
         @ViewBuilder action: @escaping () -> Action = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.s8) {
            GFIcon(kind: icon, size: 24, stroke: theme.colors.textTertiary)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.colors.fillControl))
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
    EmptyState(icon: .pr, title: "No pull requests open",
               subtitle: "When you open a PR it'll show up here.") {
        GFButton(title: "New PR", style: .primary) { }
    }
    .frame(width: 480, height: 320)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
