import SwiftUI

/// Themed `TextField` (redesign spec §5).
struct GFTextField: View {
    let placeholder: String
    @Binding var text: String

    @Environment(\.appTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .textRole(.body)
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: theme.density.metrics.fieldHeight)
            .background(shape.fill(fieldBackground))
            .overlay(shape.strokeBorder(focused ? theme.colors.accent : theme.colors.strokeControl, lineWidth: 1))
            // Redesign spec §5: focus adds a 3 pt accent ring at 30 %.
            .background(
                shape.stroke(theme.colors.accent.opacity(focused ? 0.3 : 0), lineWidth: 3)
                    .padding(-1.5)
            )
            .focused($focused)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.control) }

    private var fieldBackground: Color {
        theme.effectiveMode == .dark ? .black.opacity(0.3) : .white
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
