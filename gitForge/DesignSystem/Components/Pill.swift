import SwiftUI

/// `.gf-pill` — small ahead/behind/dirty/clean tag.
struct Pill: View {
    enum Kind { case up, down, dirty, clean, neutral }

    let text: String
    var kind: Kind = .neutral

    @Environment(\.appTheme) private var theme

    var body: some View {
        let p = theme.palette
        let (fg, bg, border): (Color, Color, Color) = {
            switch kind {
            case .up:
                return (p.ok, p.ok.opacity(0.12), p.ok.opacity(0.3))
            case .down:
                return (p.info, p.info.opacity(0.12), p.info.opacity(0.3))
            case .dirty:
                return (p.mod, p.mod.opacity(0.12), p.mod.opacity(0.3))
            case .clean:
                return (p.fg3, p.bg3, p.line)
            case .neutral:
                return (p.fg3, p.bg3, p.line)
            }
        }()
        return Text(text)
            .font(AppFont.mono(10, family: theme.monoFont))
            .foregroundStyle(fg)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.hairline)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).stroke(border, lineWidth: 1))
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
            Pill(text: "clean", kind: .clean)
        } else {
            HStack(spacing: DesignTokens.Spacing.xxs) {
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
            Pill(text: "clean", kind: .clean)
            Pill(text: "neutral", kind: .neutral)
        }
        StatusPills(ahead: 7, behind: 1, dirty: 3)
        StatusPills(ahead: 0, behind: 0, dirty: 0)
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
