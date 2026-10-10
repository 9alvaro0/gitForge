import Foundation

/// Pure sRGB maths on `0xRRGGBB` values. `nonisolated` so the commit graph
/// renderer, which runs off the main actor, can use it.
nonisolated enum ColorMath {
    static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    static func hex(r: Double, g: Double, b: Double) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// WCAG 2 relative luminance.
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let c = components(hex)
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    /// WCAG 2 contrast ratio, `1...21`.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// HSV hue in degrees, `0..<360`. Greys report 0.
    static func hue(_ hex: UInt32) -> Double {
        let c = components(hex)
        let maxV = max(c.r, c.g, c.b), minV = min(c.r, c.g, c.b)
        let delta = maxV - minV
        guard delta > 0 else { return 0 }
        let sector: Double
        if maxV == c.r {
            sector = (c.g - c.b) / delta
        } else if maxV == c.g {
            sector = (c.b - c.r) / delta + 2
        } else {
            sector = (c.r - c.g) / delta + 4
        }
        let degrees = sector * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Shortest distance between two hues on the colour wheel, `0...180`.
    static func hueDistance(_ a: UInt32, _ b: UInt32) -> Double {
        let d = abs(hue(a) - hue(b))
        return min(d, 360 - d)
    }

    /// Straight sRGB blend: `fraction` 0 returns `hex`, 1 returns `target`.
    static func mix(_ hex: UInt32, toward target: UInt32, fraction: Double) -> UInt32 {
        let a = components(hex), b = components(target)
        return Self.hex(
            r: a.r + (b.r - a.r) * fraction,
            g: a.g + (b.g - a.g) * fraction,
            b: a.b + (b.b - a.b) * fraction
        )
    }

    /// Steps `hex` toward `target` in 5 % increments until it reaches `ratio`
    /// against `background`. Returns `target` when no step gets there.
    static func raise(_ hex: UInt32, toContrast ratio: Double, on background: UInt32, toward target: UInt32) -> UInt32 {
        for step in 0...20 {
            let candidate = mix(hex, toward: target, fraction: Double(step) * 0.05)
            if contrast(candidate, background) >= ratio { return candidate }
        }
        return target
    }
}
