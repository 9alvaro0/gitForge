import SwiftUI

struct PullsTokenSheet: View {
    let host: RemoteHost
    @Binding var draft: String
    @Binding var error: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("\(host.provider.label) token")
                .textRole(.title)
                .foregroundStyle(theme.colors.textPrimary)
            Text("Token will be stored in macOS Keychain for \(host.host).")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
            Text(scopeHint)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("ghp_… / glpat_…", text: $draft)
                .textFieldStyle(.plain)
                .font(AppFont.font(.mono, monoFamily: theme.monoFont))
                .padding(.horizontal, Spacing.s8)
                .frame(height: theme.density.metrics.fieldHeight)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.effectiveMode == .dark ? Color.black.opacity(0.3) : .white))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(theme.colors.strokeControl, lineWidth: 1))
            if let error {
                Text(error)
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.del)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                GFButton(title: "Cancel", action: onCancel)
                Spacer()
                GFButton(title: "Save", style: .primary, action: onSave)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.s20)
        .frame(width: 460)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
    }

    private var scopeHint: String {
        switch host.provider {
        case .github: "Required scope: `repo` (private) or `public_repo`."
        case .gitlab: "Required scope: `read_api` (or `api` for write actions)."
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var draft = ""
    @Previewable @State var error: String? = nil
    PullsTokenSheet(
        host: .previewGitHub,
        draft: $draft,
        error: $error,
        onCancel: {}, onSave: {}
    )
    .appTheme(theme)
}
