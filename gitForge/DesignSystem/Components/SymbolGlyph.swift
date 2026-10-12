import SwiftUI

/// An SF Symbol drawn at a box size: the symbol at 0.8 of it (symbols fill
/// more of their point size than the old line icons did), centred in a
/// `size` square unless `framed` is off. Decorative: hidden from VoiceOver.
struct SymbolGlyph: View {
    let symbol: String
    let size: CGFloat
    var framed = true

    init(_ symbol: String, size: CGFloat, framed: Bool = true) {
        self.symbol = symbol
        self.size = size
        self.framed = framed
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.8, weight: .medium))
            .frame(width: framed ? size : nil, height: framed ? size : nil)
            .accessibilityHidden(true)
    }
}
