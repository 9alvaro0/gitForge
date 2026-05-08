import SwiftUI

/// `.gf-statusbar` — bottom strip with branch + ahead/behind + staged + last fetch + online.
struct AppStatusBar: View {
    let branch: String?
    let ahead: Int
    let behind: Int
    let staged: Int
    let unstaged: Int
    let lastFetch: Date?
    let online: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxl) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                GFIcon(kind: .branch, size: 11, stroke: theme.palette.fg2)
                Text(branch ?? "—")
                    .font(AppFont.mono(11, family: theme.monoFont))
            }
            .foregroundStyle(theme.palette.fg2)

            HStack(spacing: DesignTokens.Spacing.none) {
                Text("↑\(ahead)").foregroundStyle(theme.palette.ok)
                Text("↓\(behind)").foregroundStyle(theme.palette.info).padding(.leading, DesignTokens.Spacing.xs)
            }
            .font(AppFont.mono(11, family: theme.monoFont))

            Text("\(staged) staged · \(unstaged) unstaged")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg2)

            Spacer()

            Text(fetchLabel)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
            Text("UTF-8")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
            Text("LF")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
            HStack(spacing: DesignTokens.Spacing.sm) {
                Circle().fill(online ? theme.palette.ok : theme.palette.fg4)
                    .frame(width: 7, height: 7)
                Text(online ? "online" : "offline")
                    .font(AppFont.mono(11, family: theme.monoFont))
            }
            .foregroundStyle(theme.palette.fg2)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .frame(height: DesignTokens.Window.statusbarHeight)
        .background(theme.palette.bg1)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.palette.lineStrong).frame(height: 1)
        }
    }

    private var fetchLabel: String {
        guard let lastFetch else { return "no fetch yet" }
        let s = Int(Date().timeIntervalSince(lastFetch))
        if s < 60 { return "last fetch · \(s)s ago" }
        let m = s / 60
        if m < 60 { return "last fetch · \(m)m ago" }
        let h = m / 60
        if h < 24 { return "last fetch · \(h)h ago" }
        return "last fetch · \(h / 24)d ago"
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: DesignTokens.Spacing.none) {
        Spacer()
        AppStatusBar(branch: "feat/commit-graph",
                     ahead: 7, behind: 1,
                     staged: 3, unstaged: 4,
                     lastFetch: Date().addingTimeInterval(-120),
                     online: true)
    }
    .frame(width: 1100, height: 200)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
