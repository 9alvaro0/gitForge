import SwiftUI

struct StashCreateSheet: View {
    @Binding var message: String
    let onCancel: () -> Void
    let onStash: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("Stash current changes").font(AppFont.sans(14, weight: .semibold))
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Message (optional)")
                    .font(AppFont.sans(11, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                GFTextField(placeholder: "WIP: refactor commit graph", text: $message)
            }
            HStack {
                GFButton(title: "Cancel", action: onCancel)
                Spacer()
                GFButton(title: "Stash", style: .primary, action: onStash)
            }
        }
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 420)
        .background(theme.palette.bg1)
        .appTheme(theme)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var message = ""
    StashCreateSheet(message: $message, onCancel: {}, onStash: {})
        .appTheme(theme)
}
