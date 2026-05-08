import SwiftUI

/// Color tokens for the commit graph. Pinned trunks (main / develop / trunk)
/// get fixed, saturated hues so the eye instantly anchors on them; everything
/// else hashes into `lanes` so neighbouring branches contrast well even in
/// dense histories.
///
/// These colours are deliberately theme-agnostic: a branch line should keep
/// the same hue when the user toggles dark/light so the mental map of the
/// graph stays stable.
enum GraphPalette {
    /// main / master — vivid cobalt. Reads as the canonical production trunk.
    static let main = Color(red: 0.18, green: 0.55, blue: 1.00)
    /// develop / dev — warm amber. Strong contrast against `main`.
    static let develop = Color(red: 1.00, green: 0.62, blue: 0.10)
    /// trunk — deep indigo, distinct from `main` but in the "stable" family.
    static let trunk = Color(red: 0.40, green: 0.30, blue: 0.95)

    /// 12 distinct hues so neighboring branches contrast well even in dense histories.
    static let lanes: [Color] = [
        Color(red: 0.30, green: 0.65, blue: 0.95),
        Color(red: 0.97, green: 0.50, blue: 0.30),
        Color(red: 0.40, green: 0.78, blue: 0.50),
        Color(red: 0.85, green: 0.45, blue: 0.85),
        Color(red: 0.95, green: 0.78, blue: 0.30),
        Color(red: 0.55, green: 0.50, blue: 0.95),
        Color(red: 0.30, green: 0.80, blue: 0.80),
        Color(red: 0.92, green: 0.42, blue: 0.55),
        Color(red: 0.55, green: 0.78, blue: 0.40),
        Color(red: 0.78, green: 0.55, blue: 0.30),
        Color(red: 0.40, green: 0.55, blue: 0.85),
        Color(red: 0.85, green: 0.65, blue: 0.85),
    ]
}
