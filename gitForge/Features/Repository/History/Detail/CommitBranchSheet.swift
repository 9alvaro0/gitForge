import SwiftUI

struct CommitBranchSheet: View {
    let commitShortSha: String
    @Binding var name: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("New branch from \(commitShortSha)")
                .font(AppFont.sans(14, weight: .semibold))
            GFTextField(placeholder: "feat/awesome", text: $name)
            HStack {
                GFButton(title: "Cancel", action: onCancel)
                Spacer()
                GFButton(title: "Create & checkout", style: .primary,
                         disabled: name.isEmpty, action: onConfirm)
            }
        }
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(theme)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var name = ""
    CommitBranchSheet(commitShortSha: "abc1234", name: $name, onCancel: {}, onConfirm: {})
        .appTheme(theme)
}
