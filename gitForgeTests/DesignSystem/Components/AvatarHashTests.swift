import Foundation
import Testing
@testable import gitForge

@Suite("Avatar — colour hash")
@MainActor
struct AvatarHashTests {

    @Test("The palette index is always in range, for any seed")
    func inRange() {
        for seed in ["", "a", "Alvaro Guerra", "9alvaro0@gmail.com", String(repeating: "z", count: 500)] {
            let index = Avatar.paletteIndex(seed: seed, count: 6)
            #expect((0..<6).contains(index), "\(seed)")
        }
    }

    @Test("A hash of Int.min doesn't trap")
    func intMin() {
        #expect((0..<6).contains(Avatar.paletteIndex(hash: .min, count: 6)))
    }

    @Test("The same seed always gets the same colour")
    func stable() {
        #expect(Avatar.paletteIndex(seed: "lucia@forge.dev", count: 6) == Avatar.paletteIndex(seed: "lucia@forge.dev", count: 6))
    }
}
