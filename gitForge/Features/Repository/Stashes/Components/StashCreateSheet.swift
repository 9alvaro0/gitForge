import SwiftUI

struct StashCreateSheet: View {
    @Binding var message: String
    let onCancel: () -> Void
    let onStash: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Stash current changes")
                .textRole(.title)
                .foregroundStyle(theme.colors.textPrimary)
            VStack(alignment: .leading, spacing: Spacing.s6) {
                Text("Message (optional)")
                    .textRole(.callout, weight: .semibold)
                    .foregroundStyle(theme.colors.textSecondary)
                GFTextField(placeholder: "WIP: refactor commit graph", text: $message)
            }
            HStack {
                GFButton(title: "Cancel", action: onCancel)
                Spacer()
                GFButton(title: "Stash", style: .primary, action: onStash)
            }
        }
        .padding(Spacing.s20)
        .frame(width: 420)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var message = ""
    StashCreateSheet(message: $message, onCancel: {}, onStash: {})
        .appTheme(theme)
}
