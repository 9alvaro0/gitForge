import SwiftUI

/// Names a branch to create at a commit. History creates and checks it
/// out; Recover lost commits only creates it (`confirmTitle`).
struct CommitBranchSheet: View {
    let commitShortSha: String
    @Binding var name: String
    var confirmTitle = String(localized: "Create & checkout")
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("New branch from \(commitShortSha)")
                .textRole(.headline)
            GFTextField(placeholder: "feat/awesome", text: $name)
            HStack {
                GFButton(title: String(localized: "Cancel"), shortcut: .cancelAction, action: onCancel)
                Spacer()
                GFButton(title: confirmTitle, style: .primary,
                         disabled: name.isEmpty, shortcut: .defaultAction, action: onConfirm)
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
