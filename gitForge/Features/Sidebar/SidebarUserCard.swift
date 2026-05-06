import SwiftUI

/// `.gf-user` — sticky user identity card at the bottom of the sidebar.
struct SidebarUserCard: View {
    let name: String
    let online: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hex: 0x7c5cff), Color(hex: 0xc976d9)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(initials)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            Text(name)
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Circle().fill(online ? theme.palette.ok : theme.palette.fg4)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(theme.palette.bg3, lineWidth: 2))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .padding(.top, 8)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack {
        SidebarUserCard(name: "Alvaro Guerra", online: true)
        SidebarUserCard(name: "Mateo Vélez",   online: false)
    }
    .frame(width: 256)
    .padding(.vertical, 12)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
