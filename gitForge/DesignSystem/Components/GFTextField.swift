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
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .stroke(focused ? theme.palette.accent : theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular)
            )
            .focused($focused)
    }
}

/// `.gf-chip-input` — small accent-colored filter chip.
struct ChipInput: View {
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .font(AppFont.mono(11, family: theme.monoFont))
            .foregroundStyle(theme.palette.accent)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.accentSoft))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var text: String = "feat/commit-graph"
    VStack(spacing: DesignTokens.Spacing.lg) {
        GFTextField(placeholder: "Filter…", text: $text).frame(width: 300)
        GFTextField(placeholder: "Empty placeholder", text: .constant("")).frame(width: 300)
        HStack {
            ChipInput(text: "author:mvelez")
            ChipInput(text: "branch:main")
        }
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
