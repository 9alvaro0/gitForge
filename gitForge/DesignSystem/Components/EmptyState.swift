import SwiftUI

/// `.gf-empty` — centered placeholder with icon, title, subtitle.
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
        VStack(spacing: 10) {
            GFIcon(kind: icon, size: 32, stroke: theme.palette.fg4)
            Text(title)
                .font(AppFont.sans(14))
                .foregroundStyle(theme.palette.fg1)
            if let subtitle {
                Text(subtitle)
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
            }
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
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
