import SwiftUI

struct CommitActionButton: View {
    let icon: String
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
    let icon: String
    let title: String
    var destructive: Bool = false
    var trailingChevron: Bool = false
    var hovering: Bool = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Image(systemName: icon)
                .font(.system(size: 13 * 0.8, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
            Text(title)
                .textRole(.callout)
                .foregroundStyle(foreground)
            Spacer(minLength: 0)
            if trailingChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11 * 0.8, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 11, height: 11)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Spacing.s12)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(background))
        // Hover adds on top of the rest fill, so it always reads stronger.
        .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(hoverLayer))
        .overlay(RoundedRectangle(cornerRadius: Radius.controlSmall).stroke(border, lineWidth: 1))
        .contentShape(.rect(cornerRadius: Radius.controlSmall))
    }

    private var background: Color {
        destructive ? theme.colors.delSoft : theme.colors.fillControl
    }
    private var hoverLayer: Color {
        hovering && !destructive ? theme.colors.fillHover : .clear
    }
    private var foreground: Color {
        if destructive { return theme.colors.del }
        return hovering ? theme.colors.textPrimary : theme.colors.textSecondary
    }
    private var border: Color {
        if destructive { return theme.colors.del.opacity(hovering ? 0.55 : 0.3) }
        return hovering ? theme.colors.strokeControl : theme.colors.separator
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 8) {
        CommitActionButton(icon: "arrow.triangle.branch", title: "Branch", tooltip: "Create a new branch", action: {})
        CommitActionButton(icon: "exclamationmark.triangle", title: "Reset to here", tooltip: "Move HEAD here", destructive: true, action: {})
        CommitActionButtonLabel(icon: "exclamationmark.triangle", title: "Reset to here", destructive: true, trailingChevron: true)
    }
    .padding()
    .frame(width: 280)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}
