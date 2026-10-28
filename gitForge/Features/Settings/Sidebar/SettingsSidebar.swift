import SwiftUI

/// The sidebar column while the window is in Settings mode
/// (settings-redesign §4.1): the way back, the title, one row per pane and
/// the version. Presentation only; `SidebarHost` wires the stores.
struct SettingsSidebar: View {
    let selection: SettingsPane
    /// The repository "Back" returns to, or `nil` when none is open.
    let repositoryName: String?
    let version: String
    let canShowWhatsNew: Bool
    let onSelect: (SettingsPane) -> Void
    let onBack: () -> Void
    let onWhatsNew: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBackButton(repositoryName: repositoryName, action: onBack)
            Text("Settings")
                .textRole(.title)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, Spacing.s8)
                .padding(.vertical, Spacing.s12)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Spacing.s2) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsSidebarRow(pane: pane, isActive: pane == selection) { onSelect(pane) }
                }
            }
            Spacer(minLength: Spacing.s12)
            footer
        }
        .padding(.horizontal, Spacing.s8)
        .padding(.bottom, Spacing.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: Spacing.s8) {
            // The product name and its version aren't translated.
            Text(verbatim: "gitForge \(version)")
                .textRole(.caption)
                .foregroundStyle(theme.colors.textQuaternary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if canShowWhatsNew {
                Button("What's New", action: onWhatsNew)
                    .buttonStyle(.plain)
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.accent)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Spacing.s8)
        .padding(.top, Spacing.s12)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
    }
}

/// "Back to <repository>", or just "Back" without one. A long name is cut in
/// the middle so the label stays on one line in the narrowest column.
private struct SettingsBackButton: View {
    let repositoryName: String?
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s6) {
                SymbolGlyph("chevron.left", size: 14)
                label
                    .textRole(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(hovering ? theme.colors.textPrimary : theme.colors.textTertiary)
            .padding(.horizontal, Spacing.s8)
            .frame(height: theme.density.metrics.rowSidebar)
            .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering ? theme.colors.fillHover : .clear))
            .contentShape(.rect(cornerRadius: Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(String(localized: "Close Settings") + " (⌘[)")
    }

    private var label: Text {
        if let repositoryName { Text("Back to \(repositoryName)") } else { Text("Back") }
    }
}

/// One pane: its tile and name, in the style of `SidebarNavItem`.
private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isActive: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s8) {
                SettingsPaneTile(pane: pane, size: 22)
                Text(pane.label)
                    .textRole(.body, weight: isActive ? .semibold : .regular)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.s8)
            // The 22 pt tile is taller than `SidebarNavItem`'s glyph.
            .frame(height: theme.density.metrics.rowSidebar + Spacing.s4)
            .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowBackground))
            .contentShape(.rect(cornerRadius: Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var rowBackground: Color {
        if isActive { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }
}

// MARK: - Previews

/// Gives a preview its own theme in the requested appearance.
private struct SettingsSidebarPreview: View {
    var scheme: ColorScheme = .dark
    var repositoryName: String? = "nimbus-api"
    var width: CGFloat = 240

    @State private var theme = AppTheme()
    @State private var selected: SettingsPane

    init(scheme: ColorScheme = .dark, repositoryName: String? = "nimbus-api",
         width: CGFloat = 240, selection: SettingsPane = .accounts) {
        self.scheme = scheme
        self.repositoryName = repositoryName
        self.width = width
        _selected = State(initialValue: selection)
    }

    var body: some View {
        SettingsSidebar(selection: selected, repositoryName: repositoryName, version: "1.6.0",
                        canShowWhatsNew: true, onSelect: { selected = $0 }, onBack: {}, onWhatsNew: {})
            .frame(width: width, height: 420)
            .background(theme.colors.bgWindow)
            .appTheme(theme)
            .preferredColorScheme(scheme)
            .onAppear { theme.systemColorScheme = scheme }
    }
}

/// 40 characters, to see the name cut in the middle.
private let longRepositoryName = "nimbus-api-gateway-service-configuration"

#Preview("Settings sidebar, dark") {
    SettingsSidebarPreview(scheme: .dark)
}

#Preview("Settings sidebar, light") {
    SettingsSidebarPreview(scheme: .light)
}

#Preview("Settings sidebar, no repository") {
    SettingsSidebarPreview(scheme: .dark, repositoryName: nil, selection: .general)
}

#Preview("Settings sidebar, long name, narrowest") {
    SettingsSidebarPreview(scheme: .light, repositoryName: longRepositoryName, width: 220, selection: .pullRequests)
}

#Preview("Settings sidebar, long name, widest") {
    SettingsSidebarPreview(scheme: .dark, repositoryName: longRepositoryName, width: 320, selection: .git)
}
