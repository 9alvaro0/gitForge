import SwiftUI

/// `.gf-input` — themed `TextField`.
struct GFTextField: View {
    let placeholder: String
    @Binding var text: String

    @Environment(\.appTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(AppFont.sans(12))
            .foregroundStyle(theme.palette.fg1)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .frame(height: DesignTokens.Control.height)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .stroke(focused ? theme.palette.accent : theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular)
            )
            .focused($focused)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var text: String = "feat/commit-graph"
    VStack(spacing: DesignTokens.Spacing.lg) {
        GFTextField(placeholder: "Filter…", text: $text).frame(width: 300)
        GFTextField(placeholder: "Empty placeholder", text: .constant("")).frame(width: 300)
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
