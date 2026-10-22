import SwiftUI

/// A notice over the whole inbox: an account to connect again, repos left
/// out by the limit.
struct ReviewsNotice: View {
    let symbol: String
    let tint: Color
    let soft: Color
    let title: String
    let detail: String?
    let action: (title: String, run: () -> Void)?

    @Environment(\.appTheme) private var theme

    var body: some View {
        // The button beside the text while both fit on their lines, else
        // under it: a narrow column doesn't cut the account's host.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s8) {
                icon
                texts
                actionButton
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                icon
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    texts
                    actionButton
                }
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(soft))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(tint.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
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
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let action {
            GFButton(title: action.title, size: .small, action: action.run)
                .fixedSize()
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: Spacing.s6) {
        ReviewsNotice(symbol: "exclamationmark.triangle.fill", tint: theme.colors.warn, soft: theme.colors.warnSoft,
                      title: "Reconnect your GitLab account", detail: "marta.ops · gitlab.example.test",
                      action: ("Reconnect…", {}))
        ReviewsNotice(symbol: "info.circle.fill", tint: theme.colors.info, soft: theme.colors.infoSoft,
                      title: "5 repositories left out (limit of 100).", detail: nil, action: nil)
    }
    .padding(Spacing.s8)
    .frame(width: 320)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
