import Foundation
import Testing
@testable import gitForge

@Suite("ColorMath")
struct ColorMathTests {

    @Test("Black on white is the WCAG maximum, a colour on itself the minimum")
    func contrastBounds() {
        #expect(abs(ColorMath.contrast(0x000000, 0xFFFFFF) - 21) < 0.01)
        #expect(abs(ColorMath.contrast(0x7C5CFF, 0x7C5CFF) - 1) < 0.0001)
    }

    @Test("Hue follows the HSV wheel; greys report 0")
    func hue() {
        #expect(ColorMath.hue(0xFF0000) == 0)
        #expect(abs(ColorMath.hue(0x00FF00) - 120) < 0.001)
        #expect(abs(ColorMath.hue(0x0000FF) - 240) < 0.001)
        #expect(abs(ColorMath.hue(0xFF0080) - 330) < 0.5)
        #expect(ColorMath.hue(0x808080) == 0)
    }

    @Test("Hue distance takes the short way round the wheel")
    func hueDistance() {
        #expect(abs(ColorMath.hueDistance(0xFF0000, 0xFF00FF) - 60) < 0.001)
        #expect(abs(ColorMath.hueDistance(0xFF0080, 0xFF8000) - 60) < 0.5)
    }

    @Test("Mixing halfway from black to white gives mid grey; the ends are the inputs")
    func mix() {
        #expect(ColorMath.mix(0x000000, toward: 0xFFFFFF, fraction: 0.5) == 0x808080)
        #expect(ColorMath.mix(0x123456, toward: 0xFFFFFF, fraction: 0) == 0x123456)
        #expect(ColorMath.mix(0x123456, toward: 0xFFFFFF, fraction: 1) == 0xFFFFFF)
    }

    @Test("Raise stops at the first step that reaches the ratio")
    func raiseReachesRatio() {
        let raised = ColorMath.raise(0x555555, toContrast: 7, on: 0x000000, toward: 0xFFFFFF)
        #expect(ColorMath.contrast(raised, 0x000000) >= 7)
        #expect(raised != 0xFFFFFF)
    }

    @Test("Raise terminates on an impossible ratio and returns the target")
    func raiseImpossible() {
        #expect(ColorMath.raise(0x555555, toContrast: 30, on: 0x000000, toward: 0xFFFFFF) == 0xFFFFFF)
    }

    @Test("Hex round-trips through components")
    func roundTrip() {
        let c = ColorMath.components(0x7C5CFF)
        #expect(ColorMath.hex(r: c.r, g: c.g, b: c.b) == 0x7C5CFF)
    }
}
