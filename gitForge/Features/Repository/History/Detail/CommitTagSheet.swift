import SwiftUI

struct CommitTagSheet: View {
    let commitShortSha: String
    @Binding var name: String
    @Binding var message: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("New tag at \(commitShortSha)")
                .font(AppFont.sans(14, weight: .semibold))
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Name")
                    .font(AppFont.sans(11, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                GFTextField(placeholder: "v1.2.3", text: $name)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Message (optional — annotated tag if set)")
                    .font(AppFont.sans(11, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                GFTextField(placeholder: "Release 1.2.3", text: $message)
            }
            HStack {
                GFButton(title: "Cancel", action: onCancel)
                Spacer()
                GFButton(title: "Create tag", style: .primary,
                         disabled: name.isEmpty, action: onConfirm)
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
    @Previewable @State var name = ""
    @Previewable @State var message = ""
    CommitTagSheet(
        commitShortSha: "abc1234", name: $name, message: $message,
        onCancel: {}, onConfirm: {}
    )
    .appTheme(theme)
}
