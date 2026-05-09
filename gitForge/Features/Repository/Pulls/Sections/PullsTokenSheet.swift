import SwiftUI

struct PullsTokenSheet: View {
    let host: RemoteHost
    @Binding var draft: String
    @Binding var error: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("\(host.provider.label) token")
                .font(AppFont.sans(14, weight: .semibold))
            Text("Token will be stored in macOS Keychain for \(host.host).")
                .font(AppFont.sans(11))
                .foregroundStyle(theme.palette.fg3)
            Text(scopeHint)
                .font(AppFont.sans(11))
                .foregroundStyle(theme.palette.fg3)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("ghp_… / glpat_…", text: $draft)
                .textFieldStyle(.plain)
                .font(AppFont.mono(12, family: theme.monoFont))
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(height: DesignTokens.Control.height)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular))
            if let error {
                Text(error)
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.del)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                GFButton(title: "Cancel", action: onCancel)
                Spacer()
                GFButton(title: "Save", style: .primary, action: onSave)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 460)
        .background(theme.palette.bg1)
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
        host: RemoteHost(provider: .github, host: "github.com", owner: "9alvaro0", repo: "gitForge"),
        draft: $draft,
        error: $error,
        onCancel: {}, onSave: {}
    )
    .appTheme(theme)
}
