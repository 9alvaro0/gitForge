import Foundation
import Testing
@testable import gitForge

@Suite("AppTheme — Increase contrast")
@MainActor
struct AppThemeContrastTests {
    @Test("Turning Increase contrast on and off swaps the colours to and from the high-contrast variant")
    func followsContrast() {
        let theme = AppTheme()
        let isDark = theme.effectiveMode == .dark
        theme.increasedContrast = true
        #expect(theme.colors == GFColors.make(ThemeVariant(isDark: isDark, highContrast: true), accent: theme.accentSwatch))
        theme.increasedContrast = false
        #expect(theme.colors == GFColors.make(ThemeVariant(isDark: isDark, highContrast: false), accent: theme.accentSwatch))
    }
}
