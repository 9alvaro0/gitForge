import SwiftUI

/// `.gf-pill` — small ahead/behind/dirty/neutral tag.
struct Pill: View {
    enum Kind { case up, down, dirty, neutral }

    let text: String
    var kind: Kind = .neutral

    @Environment(\.appTheme) private var theme

    var body: some View {
        let c = theme.colors
        let (fg, bg): (Color, Color) = {
            switch kind {
            case .up:      return (c.ok, c.okSoft)
            case .down:    return (c.info, c.infoSoft)
            case .dirty:   return (c.mod, c.modSoft)
            case .neutral: return (c.textTertiary, c.fillControl)
            }
        }()
        return Text(text)
            .textRole(.monoSmall)
            .foregroundStyle(fg)
            .padding(.horizontal, Spacing.s6)
            .frame(height: 18)
            .background(Capsule().fill(bg))
    }
}


/// Combo of ahead/behind/dirty pills as in the sidebar repo row.
struct StatusPills: View {
    let ahead: Int
    let behind: Int
    let dirty: Int
    /// When false, renders a shimmer placeholder pill instead of "clean".
    /// Avoids the false "clean" flash before the first status fetch lands.
    var loaded: Bool = true

    var body: some View {
        if !loaded {
            Pill(text: "···", kind: .neutral)
                .skeleton(true)
        } else if ahead == 0 && behind == 0 && dirty == 0 {
            Pill(text: "clean", kind: .neutral)
        } else {
            HStack(spacing: Spacing.s2) {
                if ahead > 0  { Pill(text: "↑\(ahead)",  kind: .up) }
                if behind > 0 { Pill(text: "↓\(behind)", kind: .down) }
                if dirty > 0  { Pill(text: "●\(dirty)",  kind: .dirty) }
            }
        }
    }
}

#Preview("Pill kinds") {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
        HStack {
            Pill(text: "↑5", kind: .up)
            Pill(text: "↓3", kind: .down)
            Pill(text: "●2", kind: .dirty)
            Pill(text: "neutral", kind: .neutral)
        }
        StatusPills(ahead: 7, behind: 1, dirty: 3)
        StatusPills(ahead: 0, behind: 0, dirty: 0)
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
