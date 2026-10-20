import SwiftUI

/// Sparkle's update policy. Hidden when there is no updater (previews).
struct UpdatesSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(Updater.self) private var updater: Updater?

    var body: some View {
        if let updater {
            SettingsSection(title: "Updates", subtitle: versionSubtitle) {
                HStack(alignment: .top) {
                    SettingsRowLabel(text: "Install automatically")
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Toggle("", isOn: Binding(
                            get: { updater.installsUpdatesAutomatically },
                            set: { updater.setInstallsUpdatesAutomatically($0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        Text("Download updates in the background and install them when you quit gitForge. When off, gitForge asks before downloading.")
                            .textRole(.callout)
                            .foregroundStyle(theme.colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.s12)
                .padding(.vertical, Spacing.s8)
                SettingsDivider()
                HStack(alignment: .center) {
                    SettingsRowLabel(text: "Check now")
                    if let ready = updater.readyUpdate {
                        GFButton(title: "Restart to Update to \(ready.version)", style: .primary, size: .small) {
                            updater.installAndRelaunch()
                        }
                    } else {
                        GFButton(title: "Check for Updates…", size: .small,
                                 disabled: !updater.canCheckForUpdates) {
                            updater.checkForUpdates()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.s12)
                .padding(.vertical, Spacing.s8)
            }
        }
    }

    private var versionSubtitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "gitForge \(version). Checks for updates every 6 hours."
    }
}
