import SwiftUI

/// Split-button variant of `ToolButton`: the main pill triggers a default
/// action, and a chevron on the right opens a menu with explicit overrides.
/// Shares the same look as `ToolButton` so toolbar rows stay consistent.
struct SplitToolButton<Menu: View>: View {
    let kind: GFIconKind
    var label: String
    var badge: Int? = nil
    var primary: Bool = false
    var loading: Bool = false
    var disabled: Bool = false
    var action: () -> Void
    @ViewBuilder var menu: () -> Menu

    @Environment(\.appTheme) private var theme
    @State private var hoveringMain = false
    @State private var hoveringChev = false

    var body: some View {
        HStack(spacing: 0) {
            mainPill
            divider
            chevronPill
        }
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(bg))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(border, lineWidth: 1))
        .opacity(disabled ? 0.5 : 1)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private var mainPill: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    SpinnerGlyph(color: fg)
                } else {
                    GFIcon(kind: kind, size: 14, stroke: fg)
                }
                Text(label).font(AppFont.sans(12))
                if let badge, badge > 0, !loading {
                    Text("\(badge)")
                        .font(AppFont.mono(10, family: theme.monoFont))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(badgeBg))
                        .foregroundStyle(badgeFg)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(fg)
            .background(hoveringMain ? hoverBg : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled || loading)
        .onHover { hoveringMain = $0 }
    }

    private var divider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(width: 1, height: 18)
    }

    private var chevronPill: some View {
        SwiftUI.Menu {
            menu()
        } label: {
            GFIcon(kind: .chevD, size: 12, stroke: fg)
                .frame(width: 22, height: 28)
                .foregroundStyle(fg)
                .background(hoveringChev ? hoverBg : .clear)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(disabled || loading)
        .onHover { hoveringChev = $0 }
    }

    private var bg: Color {
        primary ? theme.palette.accent : theme.palette.bg3
    }
    private var hoverBg: Color {
        primary ? Color.white.opacity(0.10) : theme.palette.bg4
    }
    private var fg: Color {
        primary ? theme.palette.accentFg : theme.palette.fg2
    }
    private var border: Color {
        primary ? theme.palette.accent : theme.palette.line
    }
    private var dividerColor: Color {
        primary ? Color.white.opacity(0.22) : theme.palette.line
    }
    private var badgeBg: Color {
        primary ? Color.white.opacity(0.22) : theme.palette.bg2
    }
    private var badgeFg: Color {
        primary ? .white : theme.palette.fg1
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 10) {
        HStack {
            SplitToolButton(kind: .pull, label: "Pull", badge: 2, action: {}) {
                Button("Pull --ff-only") {}
                Button("Pull --rebase") {}
            }
            SplitToolButton(kind: .push, label: "Push", badge: 5, primary: true, action: {}) {
                Button("Push") {}
                Button("Push --force-with-lease", role: .destructive) {}
            }
        }
        HStack {
            SplitToolButton(kind: .pull, label: "Pulling", badge: 2, loading: true, action: {}) {
                Button("…") {}
            }
            SplitToolButton(kind: .push, label: "Pushing", badge: 5, primary: true, loading: true, action: {}) {
                Button("…") {}
            }
        }
    }
    .padding(20)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
