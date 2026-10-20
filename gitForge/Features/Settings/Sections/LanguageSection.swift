import AppKit
import SwiftUI

/// App language override. macOS resolves the language when the app launches,
/// so a change shows a restart prompt instead of applying live.
struct LanguageSection: View {
    @Environment(\.appTheme) private var theme

    @State private var selection: AppLanguage? = AppLanguageStore().override

    /// What this process launched with; a different selection needs a restart.
    private static let launchOverride = AppLanguageStore().override

    var body: some View {
        SettingsSection(title: String(localized: "Language")) {
            HStack(alignment: .top) {
                SettingsRowLabel(text: String(localized: "App language"))
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    SettingsPicker(current: title(for: selection)) {
                        Button(String(localized: "System default")) { pick(nil) }
                        Divider()
                        ForEach(AppLanguage.allCases) { language in
                            Button(language.nativeName) { pick(language) }
                        }
                    }
                    .frame(maxWidth: 240)
                    if selection != Self.launchOverride {
                        HStack(spacing: Spacing.s8) {
                            Text("Restart gitForge to apply the new language.")
                                .textRole(.callout)
                                .foregroundStyle(theme.colors.textSecondary)
                            GFButton(title: String(localized: "Restart now"), size: .small) { relaunch() }
                        }
                    } else {
                        Text("“System default” follows the language set in System Settings.")
                            .textRole(.callout)
                            .foregroundStyle(theme.colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.s12)
            .padding(.vertical, Spacing.s8)
        }
    }

    private func title(for language: AppLanguage?) -> String {
        language?.nativeName ?? String(localized: "System default")
    }

    private func pick(_ language: AppLanguage?) {
        selection = language
        AppLanguageStore().setOverride(language)
    }

    /// Opens a fresh instance, then quits this one.
    private func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        Task {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            _ = try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            NSApp.terminate(nil)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    LanguageSection()
        .frame(width: 720)
        .padding(Spacing.s20)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
