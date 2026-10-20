import SwiftUI

struct CommitTagSheet: View {
    let commitShortSha: String
    @Binding var name: String
    @Binding var message: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("New tag at \(commitShortSha)")
                .textRole(.headline)
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Name")
                    .textRole(.caption, weight: .medium)
                    .foregroundStyle(theme.colors.textTertiary)
                GFTextField(placeholder: "v1.2.3", text: $name)
            }
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Message (optional — annotated tag if set)")
                    .textRole(.caption, weight: .medium)
                    .foregroundStyle(theme.colors.textTertiary)
                GFTextField(placeholder: String(localized: "Release 1.2.3"), text: $message)
            }
            HStack {
                GFButton(title: String(localized: "Cancel"), action: onCancel)
                Spacer()
                GFButton(title: String(localized: "Create tag"), style: .primary,
                         disabled: name.isEmpty, action: onConfirm)
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
    @Previewable @State var name = ""
    @Previewable @State var message = ""
    CommitTagSheet(
        commitShortSha: "abc1234", name: $name, message: $message,
        onCancel: {}, onConfirm: {}
    )
    .appTheme(theme)
}
