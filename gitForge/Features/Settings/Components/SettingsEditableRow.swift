import SwiftUI

/// Editing state lives here on purpose — earlier revisions hoisted it to a
/// parent-level `EditingField` enum, which forced every section using more
/// than one editable row to coordinate which one was active. Keeping it
/// local lets each row stay independent.
struct SettingsEditableRow: View {
    let label: String
    let value: String?
    var mono: Bool = false
    var placeholder: String = ""
    /// Receives the trimmed string, or `nil` when the user blanked the
    /// field. Caller persists and surfaces errors.
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
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
    }

    private var editingControls: some View {
        HStack {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .textRole(mono ? .mono : .body)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, Spacing.s8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.bgContent))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(theme.colors.accent, lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .onSubmit { commit() }
            GFButton(title: "Save", style: .primary, size: .small) { commit() }
            GFButton(title: "Cancel", size: .small) { editing = false }
        }
    }

    private var displayControls: some View {
        HStack {
            Text(value ?? "—")
                .textRole(mono ? .mono : .body)
                .foregroundStyle(value == nil ? theme.colors.textTertiary : theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            GFButton(title: "Edit", size: .small) {
                draft = value ?? ""
                editing = true
            }
        }
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
    VStack(spacing: 0) {
        SettingsEditableRow(label: "Name", value: name) { name = $0 }
        SettingsDivider()
        SettingsEditableRow(label: "Signing key", value: key, mono: true,
                            placeholder: "GPG / SSH key id (optional)") { key = $0 }
    }
    .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(theme.colors.separator, lineWidth: 1))
    .frame(width: 560)
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
