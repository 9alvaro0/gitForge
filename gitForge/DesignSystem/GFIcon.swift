import SwiftUI

/// 16×16 line-style glyphs ported from `components.jsx` (`I.*`) — 1.5pt stroke,
/// round caps + joins. Pairs of `(stroke, fill)` paths so we can share the same
/// renderer for plain, mixed and fully-filled glyphs.
enum GFIconKind: String, CaseIterable, Sendable {
    case graph, diff, branch, pr, conflict, blame, clone, settings, terminal
    case search, plus, minus, dot, chevR, chevD, arrowU, arrowD
    case pull, push, fetch, stash, folder, cmd, check, x, ext
    case diamond, square, warn, more, user, copy
}

struct GFIcon: View {
    let kind: GFIconKind
    var size: CGFloat = 16
    var stroke: Color = .primary
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { ctx, rect in
            let scale = min(rect.width, rect.height) / 16.0
            ctx.translateBy(x: (rect.width - 16 * scale) / 2,
                            y: (rect.height - 16 * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            let style = StrokeStyle(lineWidth: lineWidth / scale, lineCap: .round, lineJoin: .round)
            for piece in GFIconLibrary.pieces(for: kind) {
                if piece.fill {
                    ctx.fill(piece.path, with: .color(stroke))
                } else {
                    ctx.stroke(piece.path, with: .color(stroke), style: style)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct GFIconPiece {
    let path: Path
    let fill: Bool
}

enum GFIconLibrary {
    static func pieces(for kind: GFIconKind) -> [GFIconPiece] {
        switch kind {
        case .graph:    return graph
        case .diff:     return diff
        case .branch:   return branch
        case .pr:       return pr
        case .conflict: return conflict
        case .blame:    return blame
        case .clone:    return clone
        case .settings: return settings
        case .terminal: return terminal
        case .search:   return search
        case .plus:     return plus
        case .minus:    return minus
        case .dot:      return dot
        case .chevR:    return chevR
        case .chevD:    return chevD
        case .arrowU:   return arrowU
        case .arrowD:   return arrowD
        case .pull:     return pull
        case .push:     return push
        case .fetch:    return fetch
        case .stash:    return stash
        case .folder:   return folder
        case .cmd:      return cmd
        case .check:    return check
        case .x:        return xMark
        case .ext:      return ext
        case .diamond:  return diamond
        case .square:   return square
        case .warn:     return warn
        case .more:     return more
        case .user:     return user
        case .copy:     return copyIcon
        }
    }

    // MARK: glyphs

    private static var graph: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 3));  p.addLine(to: CGPoint(x: 4, y: 7))
        p.move(to: CGPoint(x: 4, y: 7));  p.addLine(to: CGPoint(x: 4, y: 13))
        p.move(to: CGPoint(x: 4, y: 7));  p.addQuadCurve(to: CGPoint(x: 12, y: 10), control: CGPoint(x: 8, y: 7))
        p.move(to: CGPoint(x: 12, y: 3)); p.addLine(to: CGPoint(x: 12, y: 7))
        p.move(to: CGPoint(x: 12, y: 7)); p.addLine(to: CGPoint(x: 12, y: 13))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var diff: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 4));  p.addLine(to: CGPoint(x: 9,  y: 4))
        p.move(to: CGPoint(x: 3, y: 8));  p.addLine(to: CGPoint(x: 7,  y: 8))
        p.move(to: CGPoint(x: 3, y: 12)); p.addLine(to: CGPoint(x: 9,  y: 12))
        p.move(to: CGPoint(x: 11, y: 6)); p.addLine(to: CGPoint(x: 11, y: 12))
        p.move(to: CGPoint(x: 9,  y: 10)); p.addLine(to: CGPoint(x: 11, y: 12)); p.addLine(to: CGPoint(x: 13, y: 10))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var branch: [GFIconPiece] {
        var p = Path()
        p.addEllipse(in: CGRect(x: 2.5, y: 2,   width: 3, height: 3))
        p.addEllipse(in: CGRect(x: 2.5, y: 11,  width: 3, height: 3))
        p.addEllipse(in: CGRect(x: 10.5, y: 4.5, width: 3, height: 3))
        p.move(to: CGPoint(x: 4, y: 5));  p.addLine(to: CGPoint(x: 4, y: 11))
        p.move(to: CGPoint(x: 4, y: 9));  p.addQuadCurve(to: CGPoint(x: 8, y: 5.5), control: CGPoint(x: 4, y: 5.5))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var pr: [GFIconPiece] {
        var p = Path()
        p.addEllipse(in: CGRect(x: 2.5,  y: 2,   width: 3, height: 3))
        p.addEllipse(in: CGRect(x: 2.5,  y: 11,  width: 3, height: 3))
        p.addEllipse(in: CGRect(x: 10.5, y: 11,  width: 3, height: 3))
        p.move(to: CGPoint(x: 4,  y: 5));  p.addLine(to: CGPoint(x: 4,  y: 11))
        p.move(to: CGPoint(x: 12, y: 4));  p.addLine(to: CGPoint(x: 12, y: 11))
        p.move(to: CGPoint(x: 9.5, y: 2)); p.addLine(to: CGPoint(x: 11, y: 3.5)); p.addLine(to: CGPoint(x: 9.5, y: 5))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var conflict: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 1.5))
        p.addLine(to: CGPoint(x: 14, y: 13))
        p.addLine(to: CGPoint(x: 2, y: 13))
        p.closeSubpath()
        p.move(to: CGPoint(x: 8, y: 6));   p.addLine(to: CGPoint(x: 8, y: 9))
        p.move(to: CGPoint(x: 8, y: 11));  p.addLine(to: CGPoint(x: 8, y: 11.5))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var blame: [GFIconPiece] {
        var p = Path()
        p.addEllipse(in: CGRect(x: 2, y: 2, width: 12, height: 12))
        p.move(to: CGPoint(x: 8, y: 4)); p.addLine(to: CGPoint(x: 8, y: 8)); p.addLine(to: CGPoint(x: 10.5, y: 9.5))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var clone: [GFIconPiece] {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 2.5, y: 2.5, width: 8, height: 8), cornerSize: CGSize(width: 1, height: 1))
        p.move(to: CGPoint(x: 5.5, y: 5.5)); p.addLine(to: CGPoint(x: 11.5, y: 5.5)); p.addLine(to: CGPoint(x: 11.5, y: 11.5)); p.addLine(to: CGPoint(x: 5.5, y: 11.5))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var settings: [GFIconPiece] {
        var p = Path()
        p.addEllipse(in: CGRect(x: 6, y: 6, width: 4, height: 4))
        p.move(to: CGPoint(x: 8, y: 1));   p.addLine(to: CGPoint(x: 8, y: 3))
        p.move(to: CGPoint(x: 8, y: 13));  p.addLine(to: CGPoint(x: 8, y: 15))
        p.move(to: CGPoint(x: 1, y: 8));   p.addLine(to: CGPoint(x: 3, y: 8))
        p.move(to: CGPoint(x: 13, y: 8));  p.addLine(to: CGPoint(x: 15, y: 8))
        p.move(to: CGPoint(x: 3, y: 3));   p.addLine(to: CGPoint(x: 4.5, y: 4.5))
        p.move(to: CGPoint(x: 11.5, y: 11.5)); p.addLine(to: CGPoint(x: 13, y: 13))
        p.move(to: CGPoint(x: 3, y: 13));  p.addLine(to: CGPoint(x: 4.5, y: 11.5))
        p.move(to: CGPoint(x: 11.5, y: 4.5)); p.addLine(to: CGPoint(x: 13, y: 3))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var terminal: [GFIconPiece] {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 1.5, y: 3, width: 13, height: 10), cornerSize: CGSize(width: 1, height: 1))
        p.move(to: CGPoint(x: 4, y: 6.5)); p.addLine(to: CGPoint(x: 6.5, y: 8)); p.addLine(to: CGPoint(x: 4, y: 9.5))
        p.move(to: CGPoint(x: 8, y: 10));  p.addLine(to: CGPoint(x: 11, y: 10))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var search: [GFIconPiece] {
        var p = Path()
        p.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 9, height: 9))
        p.move(to: CGPoint(x: 10.5, y: 10.5)); p.addLine(to: CGPoint(x: 13.5, y: 13.5))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var plus: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 8)); p.addLine(to: CGPoint(x: 13, y: 8))
        p.move(to: CGPoint(x: 8, y: 3)); p.addLine(to: CGPoint(x: 8, y: 13))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var minus: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 8)); p.addLine(to: CGPoint(x: 13, y: 8))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var dot: [GFIconPiece] {
        var p = Path()
        p.addEllipse(in: CGRect(x: 5.5, y: 5.5, width: 5, height: 5))
        return [GFIconPiece(path: p, fill: true)]
    }

    private static var chevR: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 6, y: 3)); p.addLine(to: CGPoint(x: 11, y: 8)); p.addLine(to: CGPoint(x: 6, y: 13))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var chevD: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 6)); p.addLine(to: CGPoint(x: 8, y: 11)); p.addLine(to: CGPoint(x: 13, y: 6))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var arrowU: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 13)); p.addLine(to: CGPoint(x: 8, y: 3))
        p.move(to: CGPoint(x: 4, y: 7));  p.addLine(to: CGPoint(x: 8, y: 3)); p.addLine(to: CGPoint(x: 12, y: 7))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var arrowD: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 3));  p.addLine(to: CGPoint(x: 8, y: 13))
        p.move(to: CGPoint(x: 4, y: 9));  p.addLine(to: CGPoint(x: 8, y: 13)); p.addLine(to: CGPoint(x: 12, y: 9))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var pull: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 4));  p.addLine(to: CGPoint(x: 3, y: 12))
        p.move(to: CGPoint(x: 3, y: 4));  p.addLine(to: CGPoint(x: 1, y: 6))
        p.move(to: CGPoint(x: 3, y: 4));  p.addLine(to: CGPoint(x: 5, y: 6))
        p.move(to: CGPoint(x: 11, y: 12)); p.addLine(to: CGPoint(x: 11, y: 4))
        p.move(to: CGPoint(x: 11, y: 12)); p.addLine(to: CGPoint(x: 9, y: 10))
        p.move(to: CGPoint(x: 11, y: 12)); p.addLine(to: CGPoint(x: 13, y: 10))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var push: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 12)); p.addLine(to: CGPoint(x: 3, y: 4))
        p.move(to: CGPoint(x: 3, y: 4));  p.addLine(to: CGPoint(x: 1, y: 6))
        p.move(to: CGPoint(x: 3, y: 4));  p.addLine(to: CGPoint(x: 5, y: 6))
        p.move(to: CGPoint(x: 11, y: 4)); p.addLine(to: CGPoint(x: 11, y: 12))
        p.move(to: CGPoint(x: 11, y: 4)); p.addLine(to: CGPoint(x: 9, y: 6))
        p.move(to: CGPoint(x: 11, y: 4)); p.addLine(to: CGPoint(x: 13, y: 6))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var fetch: [GFIconPiece] {
        var p = Path()
        p.addArc(center: CGPoint(x: 8, y: 8), radius: 5.5, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.move(to: CGPoint(x: 12.5, y: 2)); p.addLine(to: CGPoint(x: 12.5, y: 5)); p.addLine(to: CGPoint(x: 9.5, y: 5))
        p.move(to: CGPoint(x: 13.5, y: 8))
        p.addArc(center: CGPoint(x: 8, y: 8), radius: 5.5, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.move(to: CGPoint(x: 3.5, y: 14)); p.addLine(to: CGPoint(x: 3.5, y: 11)); p.addLine(to: CGPoint(x: 6.5, y: 11))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var stash: [GFIconPiece] {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 2, y: 6,  width: 12, height: 3), cornerSize: CGSize(width: 0.5, height: 0.5))
        p.addRoundedRect(in: CGRect(x: 2, y: 10, width: 12, height: 3), cornerSize: CGSize(width: 0.5, height: 0.5))
        p.move(to: CGPoint(x: 3.5, y: 4)); p.addLine(to: CGPoint(x: 12.5, y: 4))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var folder: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 2, y: 4.5))
        p.addQuadCurve(to: CGPoint(x: 3, y: 3.5), control: CGPoint(x: 2, y: 3.5))
        p.addLine(to: CGPoint(x: 6, y: 3.5))
        p.addLine(to: CGPoint(x: 7.5, y: 5))
        p.addLine(to: CGPoint(x: 13, y: 5))
        p.addQuadCurve(to: CGPoint(x: 14, y: 6), control: CGPoint(x: 14, y: 5))
        p.addLine(to: CGPoint(x: 14, y: 12))
        p.addQuadCurve(to: CGPoint(x: 13, y: 13), control: CGPoint(x: 14, y: 13))
        p.addLine(to: CGPoint(x: 3, y: 13))
        p.addQuadCurve(to: CGPoint(x: 2, y: 12), control: CGPoint(x: 2, y: 13))
        p.closeSubpath()
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var cmd: [GFIconPiece] {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 3, y: 3, width: 10, height: 10), cornerSize: CGSize(width: 2, height: 2))
        p.move(to: CGPoint(x: 3, y: 6));  p.addLine(to: CGPoint(x: 13, y: 6))
        p.move(to: CGPoint(x: 3, y: 10)); p.addLine(to: CGPoint(x: 13, y: 10))
        p.move(to: CGPoint(x: 6, y: 3));  p.addLine(to: CGPoint(x: 6, y: 13))
        p.move(to: CGPoint(x: 10, y: 3)); p.addLine(to: CGPoint(x: 10, y: 13))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var check: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 8)); p.addLine(to: CGPoint(x: 6.5, y: 11.5)); p.addLine(to: CGPoint(x: 13, y: 5))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var xMark: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 4));  p.addLine(to: CGPoint(x: 12, y: 12))
        p.move(to: CGPoint(x: 12, y: 4)); p.addLine(to: CGPoint(x: 4, y: 12))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var ext: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 6, y: 3)); p.addLine(to: CGPoint(x: 3, y: 3))
        p.addLine(to: CGPoint(x: 3, y: 13)); p.addLine(to: CGPoint(x: 13, y: 13)); p.addLine(to: CGPoint(x: 13, y: 10))
        p.move(to: CGPoint(x: 9, y: 3)); p.addLine(to: CGPoint(x: 13, y: 3)); p.addLine(to: CGPoint(x: 13, y: 7))
        p.move(to: CGPoint(x: 7, y: 9)); p.addLine(to: CGPoint(x: 13, y: 3))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var diamond: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 2));  p.addLine(to: CGPoint(x: 13, y: 8))
        p.addLine(to: CGPoint(x: 8, y: 14)); p.addLine(to: CGPoint(x: 3, y: 8))
        p.closeSubpath()
        return [GFIconPiece(path: p, fill: true)]
    }

    private static var square: [GFIconPiece] {
        var p = Path()
        p.addRect(CGRect(x: 4, y: 4, width: 8, height: 8))
        return [GFIconPiece(path: p, fill: true)]
    }

    private static var warn: [GFIconPiece] {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 1.5))
        p.addLine(to: CGPoint(x: 14, y: 13))
        p.addLine(to: CGPoint(x: 2, y: 13))
        p.closeSubpath()
        p.move(to: CGPoint(x: 8, y: 6));   p.addLine(to: CGPoint(x: 8, y: 9))
        p.move(to: CGPoint(x: 8, y: 11));  p.addLine(to: CGPoint(x: 8, y: 11.3))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var more: [GFIconPiece] {
        var p = Path()
        p.addEllipse(in: CGRect(x: 2,  y: 7, width: 2, height: 2))
        p.addEllipse(in: CGRect(x: 7,  y: 7, width: 2, height: 2))
        p.addEllipse(in: CGRect(x: 12, y: 7, width: 2, height: 2))
        return [GFIconPiece(path: p, fill: true)]
    }

    private static var user: [GFIconPiece] {
        var p = Path()
        p.addEllipse(in: CGRect(x: 5.5, y: 3.5, width: 5, height: 5))
        p.move(to: CGPoint(x: 3, y: 14))
        p.addQuadCurve(to: CGPoint(x: 13, y: 14), control: CGPoint(x: 8, y: 8))
        return [GFIconPiece(path: p, fill: false)]
    }

    private static var copyIcon: [GFIconPiece] {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 5, y: 5, width: 8, height: 8), cornerSize: CGSize(width: 1, height: 1))
        p.move(to: CGPoint(x: 3, y: 11)); p.addLine(to: CGPoint(x: 3, y: 3))
        p.addLine(to: CGPoint(x: 11, y: 3))
        return [GFIconPiece(path: p, fill: false)]
    }
}

#Preview("Icon catalog") {
    @Previewable @State var theme = AppTheme()
    let columns = [GridItem(.adaptive(minimum: 60), spacing: 12)]

    ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(GFIconKind.allCases, id: \.self) { kind in
                VStack(spacing: 6) {
                    GFIcon(kind: kind, size: 22, stroke: theme.palette.fg1)
                    Text(kind.rawValue)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.palette.fg3)
                }
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.palette.bg1))
            }
        }
        .padding(16)
    }
    .frame(width: 460, height: 420)
    .background(theme.palette.bg2)
    .appTheme(theme)
}

