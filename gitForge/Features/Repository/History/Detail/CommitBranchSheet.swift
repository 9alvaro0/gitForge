import SwiftUI

struct CommitBranchSheet: View {
    let commitShortSha: String
    @Binding var name: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("New branch from \(commitShortSha)")
                .textRole(.headline)
            GFTextField(placeholder: "feat/awesome", text: $name)
            HStack {
                GFButton(title: "Cancel", action: onCancel)
                Spacer()
                GFButton(title: "Create & checkout", style: .primary,
                         disabled: name.isEmpty, action: onConfirm)
            }
        }
        .padding(Spacing.s20)
        .frame(width: 380)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var name = ""
    CommitBranchSheet(commitShortSha: "abc1234", name: $name, onCancel: {}, onConfirm: {})
        .appTheme(theme)
}
