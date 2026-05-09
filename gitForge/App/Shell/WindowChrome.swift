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
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.palette.lineStrong)
                        .frame(height: DesignTokens.Stroke.regular)
                }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.palette.bg2)
        .preferredColorScheme(preferredScheme)
        .configureWindow { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .clear
        }
    }

    /// `.system` returns `nil` so SwiftUI keeps the OS scheme; explicit
    /// modes force the window to follow the user's pick regardless of the
    /// menu-bar setting.
    private var preferredScheme: ColorScheme? {
        switch theme.mode {
        case .system: return nil
        case .dark:   return .dark
        case .light:  return .light
        }
    }

    private var titleBar: some View {
        Text(title)
            .font(AppFont.sans(12, weight: .medium))
            .foregroundStyle(theme.palette.fg2)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 100)
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
        Text("Window content goes here")
            .foregroundStyle(theme.palette.fg2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.palette.bg2)
    }
    .frame(width: 900, height: 480)
    .appTheme(theme)
}
