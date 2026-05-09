import SwiftUI

/// `.gf-user` — sticky user identity card at the bottom of the sidebar.
struct SidebarUserCard: View {
    let identity: GitIdentity
    let online: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Circle()
                .fill(LinearGradient(colors: [theme.palette.accent, gradientTail],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Text(identity.initials)
                        .font(.system(size: FontSize.footnote, weight: .bold))
                        .foregroundStyle(theme.palette.accentFg)
                }
                .frame(width: DesignTokens.IconSize.huge, height: DesignTokens.IconSize.huge)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
                Text(identity.displayName)
                    .font(AppFont.sans(12, weight: .medium))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                if let email = identity.email {
                    Text(email)
                        .font(AppFont.mono(10, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle().fill(online ? theme.palette.ok : theme.palette.fg4)
                .frame(width: DesignTokens.Spacing.md, height: DesignTokens.Spacing.md)
                .overlay(Circle().stroke(theme.palette.bg3, lineWidth: DesignTokens.Stroke.thick))
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.bottom, DesignTokens.Spacing.xs)
        .padding(.top, DesignTokens.Spacing.md)
    }

    /// Last lane swatch — used as the bottom-right stop of the avatar gradient.
    /// Falls back to `accent` if the palette is ever shrunk so we don't crash.
    private var gradientTail: Color {
        ThemePalette.lanePalette.last ?? theme.palette.accent
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack {
        SidebarUserCard(identity: .preview, online: true)
        SidebarUserCard(identity: .unknown, online: false)
    }
    .frame(width: 256)
    .padding(.vertical, DesignTokens.Spacing.xl)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
