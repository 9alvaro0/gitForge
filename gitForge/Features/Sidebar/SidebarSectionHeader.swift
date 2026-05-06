import SwiftUI

/// `.gf-side-h` — small uppercase section title in the sidebar.
struct SidebarSectionHeader: View {
    let title: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(theme.palette.fg3)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 0) {
        SidebarSectionHeader(title: "Repositories")
        SidebarSectionHeader(title: "Workspace")
    }
    .frame(width: 256)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
