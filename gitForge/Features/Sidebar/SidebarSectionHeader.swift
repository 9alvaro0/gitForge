import SwiftUI

/// `.gf-side-h` — small uppercase section title in the sidebar, with an
/// optional trailing slot for inline actions (e.g. a `+` menu next to
/// "Repositories" so the user can always add or clone, even when a repo is
/// already open and `WelcomeView` is no longer on screen).
struct SidebarSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: () -> Trailing
    @Environment(\.appTheme) private var theme

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.top, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
        SidebarSectionHeader(title: "Repositories") {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.palette.fg3)
        }
        SidebarSectionHeader(title: "Workspace")
    }
    .frame(width: 256)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
