import SwiftUI
import Observation

/// Active theme + user prefs. One instance lives in `AppState` and is injected via Environment.
@Observable
@MainActor
final class AppTheme {
    var mode: ThemeMode {
        didSet {
            persist(); refreshPalette()
        }
    }
    var accent: Color {
        didSet { persistAccent(); refreshPalette() }
    }
    var density: Density {
        didSet { persistDensity() }
    }
    var monoFont: MonoFontFamily {
        didSet { persistMonoFont() }
    }

    private(set) var palette: ThemePalette = .dark

    static let accentSwatches: [Color] = [
        Color(hex: 0x7c5cff),
        Color(hex: 0x56b497),
        Color(hex: 0xff7e6b),
        Color(hex: 0x5da4ff),
    ]

    init() {
        let savedMode = UserDefaults.standard.string(forKey: Keys.mode).flatMap(ThemeMode.init(rawValue:)) ?? .dark
        let savedDensity = UserDefaults.standard.string(forKey: Keys.density).flatMap(Density.init(rawValue:)) ?? .regular
        let savedMonoRaw = UserDefaults.standard.string(forKey: Keys.monoFont) ?? MonoFontFamily.jetbrainsMono.rawValue
        let savedMono = MonoFontFamily(rawValue: savedMonoRaw) ?? .jetbrainsMono
        let savedAccent = UserDefaults.standard.string(forKey: Keys.accent).flatMap(Color.init(stringHex:)) ?? Color(hex: 0x7c5cff)

        self.mode = savedMode
        self.accent = savedAccent
        self.density = savedDensity
        self.monoFont = savedMono
        refreshPalette()
    }

    func toggleMode() {
        mode = (mode == .dark) ? .light : .dark
    }

    private func refreshPalette() {
        palette = ThemePalette.palette(for: mode, accent: accent)
    }

    private func persist() {
        UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode)
    }
    private func persistDensity() {
        UserDefaults.standard.set(density.rawValue, forKey: Keys.density)
    }
    private func persistMonoFont() {
        UserDefaults.standard.set(monoFont.rawValue, forKey: Keys.monoFont)
    }
    private func persistAccent() {
        UserDefaults.standard.set(accent.hexString, forKey: Keys.accent)
    }

    private enum Keys {
        static let mode = "appTheme.mode"
        static let density = "appTheme.density"
        static let accent = "appTheme.accent"
        static let monoFont = "appTheme.monoFont"
    }
}

private extension Color {
    init?(stringHex: String) {
        var s = stringHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .clear
        let r = Int(round(Double(ns.redComponent) * 255))
        let g = Int(round(Double(ns.greenComponent) * 255))
        let b = Int(round(Double(ns.blueComponent) * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
