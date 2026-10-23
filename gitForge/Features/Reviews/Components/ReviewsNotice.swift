import SwiftUI

/// A notice over the whole inbox: a pattern to follow, an account to connect
/// again, repos left out by the limit. Its action, then a quieter second one
/// ("Not now").
struct ReviewsNotice: View {
    let symbol: String
    let tint: Color
    let soft: Color
    let title: String
    let detail: String?
    let action: (title: String, run: () -> Void)?
    var secondary: (title: String, run: () -> Void)? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        // The buttons beside the text while all of it fits on its lines,
        // else under it: a narrow column doesn't cut the account's host.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s8) {
                icon
                texts
                buttons
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                icon
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    texts
                    buttons
                }
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(soft))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(tint.opacity(0.3), lineWidth: 1))
        // The text and each button on their own: merged, the buttons
        // couldn't be told apart.
        .accessibilityElement(children: .contain)
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            // One width for every symbol: the texts of stacked notices line up.
            .frame(width: 16)
            .accessibilityHidden(true)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .textRole(.callout, weight: .semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttons: some View {
        if action != nil || secondary != nil {
            HStack(spacing: Spacing.s4) {
                if let action {
                    GFButton(title: action.title, size: .small, action: action.run)
                        .fixedSize()
                }
                if let secondary {
                    QuietButton(title: secondary.title, action: secondary.run)
                        .fixedSize()
                }
            }
        }
    }
}

/// A small button with no fill nor border until hovered, as `IconButton`
/// does: the way out of a notice or of the proposal in Settings › Reviews,
/// quieter than its action.
struct QuietButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .textRole(.caption, weight: .semibold)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: theme.density.metrics.buttonSmall)
                .foregroundStyle(hovering ? theme.colors.textPrimary : theme.colors.textSecondary)
                .background(RoundedRectangle(cornerRadius: Radius.controlSmall)
                    .fill(hovering ? theme.colors.fillHover : .clear))
                .contentShape(.rect(cornerRadius: Radius.controlSmall))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: Spacing.s6) {
        ReviewsNotice(symbol: "lightbulb.fill", tint: theme.colors.accent, soft: theme.colors.accentSoft,
                      title: "Your repositories seem to follow apps/*/android/*.",
                      detail: "Follow the other 2 that fit too?",
                      action: ("Follow", {}), secondary: ("Not now", {}))
        ReviewsNotice(symbol: "exclamationmark.triangle.fill", tint: theme.colors.warn, soft: theme.colors.warnSoft,
                      title: "Reconnect your GitLab account", detail: "marta.ops · gitlab.example.test",
                      action: ("Reconnect…", {}))
        ReviewsNotice(symbol: "info.circle.fill", tint: theme.colors.info, soft: theme.colors.infoSoft,
                      title: "5 repositories left out (limit of 100).",
                      detail: "Hide repositories or narrow your patterns in Settings.",
                      action: ("Open Settings", {}))
    }
    .padding(Spacing.s8)
    .frame(width: 320)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
