import SwiftUI
import Observation

/// How the app looks: appearance mode, accent, density, mono font and the
/// resolved palette. One instance lives in `WorkspaceUI` and is injected via
/// `\.appTheme`. Behaviour preferences live in `AppPreferences`.
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
    /// Live `ColorScheme` reported by the OS. The shell view keeps this in
    /// sync via `.onChange(of: \.colorScheme)`. Read by `effectiveMode` so
    /// `.system` resolves to the right palette without forcing a scheme.
    var systemColorScheme: ColorScheme = .dark {
        didSet { if mode == .system { refreshPalette() } }
    }

    /// `mode` after collapsing `.system` to whatever the OS reports. Use
    /// this anywhere a binary dark/light decision is needed.
    var effectiveMode: ThemeMode {
        if mode != .system { return mode }
        return systemColorScheme == .dark ? .dark : .light
    }

    private(set) var palette: ThemePalette = .dark

    static let accentSwatches: [Color] = [
        Color(hex: 0x7c5cff),
        Color(hex: 0x56b497),
        Color(hex: 0xff7e6b),
        Color(hex: 0x5da4ff),
    ]

    init() {
        let savedMode = UserDefaults.standard.string(forKey: Keys.mode).flatMap(ThemeMode.init(rawValue:)) ?? .system
        let savedDensity = UserDefaults.standard.string(forKey: Keys.density).flatMap(Density.init(rawValue:)) ?? .regular
        let savedMonoRaw = UserDefaults.standard.string(forKey: Keys.monoFont) ?? MonoFontFamily.systemMono.rawValue
        let savedMono = (MonoFontFamily(rawValue: savedMonoRaw)?.resolved()) ?? .systemMono
        let savedAccent = UserDefaults.standard.string(forKey: Keys.accent).flatMap(Color.init(stringHex:)) ?? Color(hex: 0x7c5cff)

        self.mode = savedMode
        self.accent = savedAccent
        self.density = savedDensity
        self.monoFont = savedMono
        refreshPalette()
    }

    private func refreshPalette() {
        palette = ThemePalette.palette(for: effectiveMode, accent: accent)
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
