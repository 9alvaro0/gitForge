import SwiftUI

/// Animation presets, so timings stay coherent across the app.
nonisolated enum Motion {
    static let fast: Animation = .easeOut(duration: 0.12)
    static let standard: Animation = .easeOut(duration: 0.18)
    static let slow: Animation = .easeInOut(duration: 0.9)
}
