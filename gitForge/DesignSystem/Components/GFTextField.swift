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
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .stroke(focused ? theme.palette.accent : theme.palette.lineStrong, lineWidth: 1)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(theme.palette.accentSoft))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var text: String = "feat/commit-graph"
    VStack(spacing: 10) {
        GFTextField(placeholder: "Filter…", text: $text).frame(width: 300)
        GFTextField(placeholder: "Empty placeholder", text: .constant("")).frame(width: 300)
        HStack {
            ChipInput(text: "author:mvelez")
            ChipInput(text: "branch:main")
        }
    }
    .padding(20)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
