import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// Mix `self` with `other` by `amount` (0…1). Mirrors CSS `color-mix(in srgb, …)`.
    func mix(_ other: Color, amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .clear
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .clear
        let t = max(0, min(1, amount))
        return Color(.sRGB,
                     red:   Double(a.redComponent)   * (1 - t) + Double(b.redComponent)   * t,
                     green: Double(a.greenComponent) * (1 - t) + Double(b.greenComponent) * t,
                     blue:  Double(a.blueComponent)  * (1 - t) + Double(b.blueComponent)  * t,
                     opacity: Double(a.alphaComponent) * (1 - t) + Double(b.alphaComponent) * t)
    }
}
