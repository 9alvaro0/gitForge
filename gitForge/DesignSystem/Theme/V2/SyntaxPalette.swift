import Foundation

/// Code colours for diffs, taken from the `Changes` (dark) and
/// `CommitDetail` (light) artboards. High contrast reuses its base theme:
/// every colour already clears AA on the high-contrast code background.
nonisolated struct SyntaxPalette: Equatable, Sendable {
    let keyword: UInt32
    let type: UInt32
    let function: UInt32
    let string: UInt32
    let number: UInt32
    let comment: UInt32
    let attribute: UInt32
    let member: UInt32
    let plain: UInt32
    /// `+` / `-` lines inside `.diff` / `.patch` files: the add / del tokens.
    let addition: UInt32
    let deletion: UInt32

    static let dark = SyntaxPalette(
        keyword: 0xFF7AB2, type: 0x7DD6C8, function: 0x8FB8FF, string: 0xF2B272, number: 0xD9C27A,
        comment: 0x8A8A98, attribute: 0xD7A6FF, member: 0xB3C0FF, plain: 0xDCDCE4,
        addition: 0x6FD8A4, deletion: 0xFF8A8A
    )

    static let light = SyntaxPalette(
        keyword: 0xB4237E, type: 0x16737F, function: 0x2F4FBF, string: 0xA4461A, number: 0x6E5200,
        comment: 0x63636E, attribute: 0x7438BC, member: 0x3A4BAE, plain: 0x24242C,
        addition: 0x167650, deletion: 0xC8373D
    )

    static func make(_ variant: ThemeVariant) -> SyntaxPalette {
        switch variant {
        case .dark, .highContrastDark: .dark
        case .light, .highContrastLight: .light
        }
    }

    var all: [(name: String, hex: UInt32)] {
        [("keyword", keyword), ("type", type), ("function", function), ("string", string), ("number", number),
         ("comment", comment), ("attribute", attribute), ("member", member), ("plain", plain),
         ("addition", addition), ("deletion", deletion)]
    }
}
