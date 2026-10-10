import SwiftUI

/// Appears under a section while some of its files are ticked: how many,
/// the section's move action (Stage / Unstage) and a confirmed Discard.
struct StagingBatchBar: View {
    let count: Int
    let moveTitle: String
    let onMove: () -> Void
    let onDiscard: () -> Void
    var disabled: Bool = false

    @Environment(\.appTheme) private var theme
    @State private var confirmingDiscard = false

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Text(count == 1 ? "1 file selected" : "\(count) files selected")
                .textRole(.callout, weight: .semibold)
                .foregroundStyle(theme.colors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            GFButton(title: moveTitle, style: .primary, size: .small, disabled: disabled, action: onMove)
            GFButton(title: "Discard…", style: .destructive, size: .small, disabled: disabled) {
                confirmingDiscard = true
            }
        }
        .padding(.leading, Spacing.s12)
        .padding(.trailing, Spacing.s6)
        .padding(.vertical, Spacing.s6)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.accentSoft))
        .padding(.top, Spacing.s6)
        .confirmationDialog(
            count == 1 ? "Discard changes to 1 file?" : "Discard changes to \(count) files?",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            // Cancel stays the default so a reflexive Return doesn't wipe work.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Discard", role: .destructive, action: onDiscard)
        } message: {
            Text("Local changes will be lost and untracked files deleted. This can't be undone.")
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    StagingBatchBar(count: 2, moveTitle: "Stage", onMove: {}, onDiscard: {})
        .padding()
        .frame(width: 440)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
