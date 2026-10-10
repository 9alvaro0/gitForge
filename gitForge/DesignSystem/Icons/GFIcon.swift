import SwiftUI

/// The app's icon vocabulary. Each kind renders an SF Symbol (redesign spec
/// §3: SF Symbols first), so glyphs pick up the system's weights and optical
/// sizes. Call sites keep naming icons by role rather than by symbol.
enum GFIconKind: String, CaseIterable, Sendable {
    case graph, diff, branch, pr, conflict, blame, clone, settings, terminal
    case search, plus, minus, dot, chevR, chevD, arrowU, arrowD
    case pull, push, fetch, stash, folder, cmd, check, x, ext
    case diamond, square, warn, more, user, copy
    /// Local-branch marker. Pairs with `.cloud` so origin reads at a glance.
    case desktop
    /// Remote-branch marker.
    case cloud
    /// Tag marker.
    case tag

    /// SF Symbol for the kind (design token sheet, "Icons").
    var symbolName: String {
        switch self {
        case .graph:    "clock.arrow.circlepath"
        case .diff:     "square.and.pencil"
        case .branch:   "arrow.triangle.branch"
        case .pr:       "arrow.triangle.pull"
        case .conflict: "exclamationmark.triangle"
        case .blame:    "person.text.rectangle"
        case .clone:    "square.and.arrow.down"
        case .settings: "gearshape"
        case .terminal: "terminal"
        case .search:   "magnifyingglass"
        case .plus:     "plus"
        case .minus:    "minus"
        case .dot:      "circle.fill"
        case .chevR:    "chevron.right"
        case .chevD:    "chevron.down"
        case .arrowU:   "arrow.up"
        case .arrowD:   "arrow.down"
        case .pull:     "arrow.down.to.line"
        case .push:     "arrow.up.to.line"
        case .fetch:    "arrow.triangle.2.circlepath"
        case .stash:    "tray.full"
        case .folder:   "folder"
        case .cmd:      "command"
        case .check:    "checkmark"
        case .x:        "xmark"
        case .ext:      "arrow.up.right.square"
        case .diamond:  "diamond"
        case .square:   "square"
        case .warn:     "exclamationmark.triangle"
        case .more:     "ellipsis"
        case .user:     "person"
        case .copy:     "doc.on.doc"
        case .desktop:  "desktopcomputer"
        case .cloud:    "cloud"
        case .tag:      "tag"
        }
    }

    /// Glyph size relative to the icon's box. SF Symbols fill more of their
    /// point size than the old 16×16 line glyphs; the dot is a small marker.
    var glyphScale: CGFloat {
        self == .dot ? 0.5 : 0.8
    }
}

struct GFIcon: View {
    let kind: GFIconKind
    var size: CGFloat = 16
    var stroke: Color = .primary
    /// Kept for source compatibility; SF Symbols take their stroke from the
    /// weight instead.
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: size * kind.glyphScale, weight: .medium))
            .foregroundStyle(stroke)
            .frame(width: size, height: size)
            // The old Canvas glyphs were silent to VoiceOver; the controls
            // that hold an icon carry the label.
            .accessibilityHidden(true)
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 8)) {
        ForEach(GFIconKind.allCases, id: \.self) { kind in
            GFIcon(kind: kind, size: 18)
                .help(kind.rawValue)
        }
    }
    .padding()
}
