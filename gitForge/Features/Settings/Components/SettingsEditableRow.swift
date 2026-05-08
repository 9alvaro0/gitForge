import SwiftUI

/// Settings row with inline edit affordance: shows the current value with an
/// "Edit" button; tapping it swaps in a `TextField` with Save/Cancel. State
/// is local so the caller only provides the current value and a commit
/// callback — no parent-level `editing` enum needed.
struct SettingsEditableRow: View {
    let label: String
    let value: String?
    var mono: Bool = false
    var placeholder: String = ""
    /// Called with the trimmed string, or `nil` if the user blanked the
    /// field. The caller is responsible for persisting and surfacing errors.
    let onCommit: (String?) -> Void

    @Environment(\.appTheme) private var theme
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack {
            SettingsRowLabel(text: label)
            if editing {
                editingControls
            } else {
                displayControls
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private var editingControls: some View {
        HStack {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(theme.palette.fg1)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(height: DesignTokens.IconSize.xxl)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).stroke(theme.palette.accent, lineWidth: DesignTokens.Stroke.regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .onSubmit { commit() }
            GFButton(title: "Save", style: .primary, size: .small) { commit() }
            GFButton(title: "Cancel", size: .small) { editing = false }
        }
    }

    private var displayControls: some View {
        HStack {
            Text(value ?? "—")
                .font(font)
                .foregroundStyle(value == nil ? theme.palette.fg3 : theme.palette.fg1)
                .frame(maxWidth: .infinity, alignment: .leading)
            GFButton(title: "Edit", size: .small) {
                draft = value ?? ""
                editing = true
            }
        }
    }

    private var font: Font {
        mono ? AppFont.mono(12, family: theme.monoFont) : AppFont.sans(12)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        onCommit(trimmed.isEmpty ? nil : trimmed)
        editing = false
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var name: String? = "Alvaro Guerra"
    @Previewable @State var key: String? = nil
    VStack(spacing: DesignTokens.Spacing.none) {
        SettingsEditableRow(label: "Name", value: name) { name = $0 }
        SettingsDivider()
        SettingsEditableRow(label: "Signing key", value: key, mono: true,
                            placeholder: "GPG / SSH key id (optional)") { key = $0 }
    }
    .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
    .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    .frame(width: 560)
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
