import SwiftUI

struct CommitActionButton: View {
    let icon: GFIconKind
    let title: String
    let tooltip: String
    var destructive: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            CommitActionButtonLabel(
                icon: icon,
                title: title,
                destructive: destructive,
                hovering: hovering
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tooltip)
    }
}

struct CommitActionButtonLabel: View {
    let icon: GFIconKind
    let title: String
    var destructive: Bool = false
    var trailingChevron: Bool = false
    var hovering: Bool = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            GFIcon(kind: icon, size: 13, stroke: foreground)
            Text(title)
                .font(AppFont.sans(12))
                .foregroundStyle(foreground)
            Spacer(minLength: 0)
            if trailingChevron {
                GFIcon(kind: .chevD, size: 11, stroke: theme.palette.fg3)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(background))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(border, lineWidth: DesignTokens.Stroke.regular))
        .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
    }

    private var background: Color {
        if destructive { return theme.palette.delSoft }
        return hovering ? theme.palette.bg4 : theme.palette.bg3
    }
    private var foreground: Color {
        if destructive { return theme.palette.del }
        return hovering ? theme.palette.fg1 : theme.palette.fg2
    }
    private var border: Color {
        if destructive { return theme.palette.del.opacity(hovering ? 0.55 : 0.3) }
        return hovering ? theme.palette.lineStrong : theme.palette.line
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 8) {
        CommitActionButton(icon: .branch, title: "Branch", tooltip: "Create a new branch", action: {})
        CommitActionButton(icon: .warn, title: "Reset to here", tooltip: "Move HEAD here", destructive: true, action: {})
        CommitActionButtonLabel(icon: .warn, title: "Reset to here", destructive: true, trailingChevron: true)
    }
    .padding()
    .frame(width: 280)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
