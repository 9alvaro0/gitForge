import SwiftUI

/// Lightweight modal used by the Branches view to capture a single branch
/// name (creating a new branch, renaming an existing one). Drives its own
/// textfield via a `@Binding` so the parent owns the value and clears it on
/// dismiss.
///
/// `confirmDisabled` is computed by the caller — it knows whether the input
/// is empty, equals the original name, etc.
struct BranchInputSheet: View {
    let title: String
    let placeholder: String
    let confirmTitle: String
    @Binding var text: String
    let confirmDisabled: Bool
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text(title).font(AppFont.sans(14, weight: .semibold))
            GFTextField(placeholder: placeholder, text: $text)
            HStack {
                GFButton(title: "Cancel", action: onCancel)
                Spacer()
                GFButton(title: confirmTitle,
                         style: .primary,
                         disabled: confirmDisabled) { onConfirm(text) }
            }
        }
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(appState.ui.theme)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var name = ""
    return BranchInputSheet(
        title: "New branch",
        placeholder: "feat/awesome",
        confirmTitle: "Create & checkout",
        text: $name,
        confirmDisabled: name.isEmpty,
        onCancel: {},
        onConfirm: { _ in }
    )
    .previewAppState(.preview)
    .appTheme(theme)
}
