import SwiftUI

/// `.gf-window` + `.gf-titlebar` — top chrome of the app.
/// Sits flush with the native traffic light buttons (which we keep visible
/// but render through a transparent native titlebar).
struct WindowChrome<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            titleBar
            Rectangle()
                .fill(theme.palette.lineStrong)
                .frame(height: 1)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.palette.bg2)
        .preferredColorScheme(theme.mode == .dark ? .dark : .light)
        .configureWindow { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
        }
    }

    private var titleBar: some View {
        ZStack {
            // Centered title.
            Text(title)
                .font(AppFont.sans(12, weight: .medium))
                .foregroundStyle(theme.palette.fg2)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 100)
        }
        .frame(maxWidth: .infinity)
        .frame(height: DesignTokens.Window.titlebarHeight)
        .background(
            LinearGradient(
                colors: [theme.palette.bg1, theme.palette.bg2],
                startPoint: .top, endPoint: .bottom
            )
        )
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    WindowChrome(title: "9alvaro0/gitForge — GitForge") {
        ZStack {
            theme.palette.bg2
            Text("Window content goes here")
                .foregroundStyle(theme.palette.fg2)
        }
    }
    .frame(width: 900, height: 480)
    .appTheme(theme)
}
