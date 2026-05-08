import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// `#RRGGBB` representation in sRGB. Used to build CSS strings the
    /// Highlightr theme parser can consume.
    var cssHex: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int(round(Double(ns.redComponent) * 255))
        let g = Int(round(Double(ns.greenComponent) * 255))
        let b = Int(round(Double(ns.blueComponent) * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
