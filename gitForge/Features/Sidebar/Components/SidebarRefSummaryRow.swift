import SwiftUI

/// Remotes / Tags summary line under the branch tree. Opens Branches.
struct SidebarRefSummaryRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s8) {
                Image(systemName: systemImage)
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16)
                Text(title)
                    .textRole(.body)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer(minLength: Spacing.s8)
                Text(detail)
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(detail)")
        .accessibilityHint("Opens Branches")
    }
}
