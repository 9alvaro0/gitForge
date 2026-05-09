import SwiftUI

/// Theme + density + diff-mode + mono font picker. Contains the only
/// two-column layout in the Settings page; the rest of the sections stack
/// rows vertically.
struct AppearanceSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(WorkspaceUI.self) private var ui

    var body: some View {
        SettingsSection(title: "Appearance") {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.xhuge) {
                appearanceColumn
                codeColumn
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appearanceColumn: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            radioRow(label: "Theme",
                     values: ThemeMode.allCases.map { ($0.rawValue, $0.label) },
                     current: ui.theme.mode.rawValue) { v in
                if let m = ThemeMode(rawValue: v) { ui.theme.mode = m }
            }
            colorRow(label: "Accent",
                     swatches: AppTheme.accentSwatches,
                     current: ui.theme.accent) { ui.theme.accent = $0 }
            radioRow(label: "Density",
                     values: Density.allCases.map { ($0.rawValue, $0.label) },
                     current: ui.theme.density.rawValue) { v in
                if let d = Density(rawValue: v) { ui.theme.density = d }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var codeColumn: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            menuPicker(label: "Mono font",
                       values: MonoFontFamily.availableCases.map { ($0.rawValue, $0.label) },
                       current: ui.theme.monoFont.resolved().rawValue) { v in
                if let f = MonoFontFamily(rawValue: v) { ui.theme.monoFont = f }
            }
            radioRow(label: "Diff view",
                     values: DiffPane.ViewMode.allCases.map { ($0.rawValue, $0.label) },
                     current: ui.theme.defaultDiffMode.rawValue) { v in
                if let m = DiffPane.ViewMode(rawValue: v) { ui.theme.defaultDiffMode = m }
            }
            menuPicker(label: "Diff context lines",
                       values: Self.contextOptions,
                       current: String(ui.theme.diffContextLines)) { v in
                if let n = Int(v) { ui.theme.diffContextLines = n }
            }
            wrapToggle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wrapToggle: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            fieldLabel("Wrap long diff lines")
            Toggle(isOn: Binding(
                get: { ui.theme.diffWrapLongLines },
                set: { ui.theme.diffWrapLongLines = $0 }
            )) {
                Text(ui.theme.diffWrapLongLines ? "Soft-wrap onto the next visual row" : "Overflow horizontally (default)")
                    .font(AppFont.sans(11))
                    .foregroundStyle(theme.palette.fg2)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private static let contextOptions: [(String, String)] = [
        ("1", "1 line"), ("3", "3 lines"), ("5", "5 lines"), ("10", "10 lines"),
    ]

    @ViewBuilder
    private func radioRow(label: String,
                          values: [(String, String)],
                          current: String,
                          onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            fieldLabel(label)
            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(values, id: \.0) { (raw, label) in
                    Button(action: { onChange(raw) }) {
                        Text(label.capitalized)
                            .font(AppFont.sans(11))
                            .padding(.horizontal, DesignTokens.Spacing.lg)
                            .frame(height: DesignTokens.IconSize.xxl)
                            .foregroundStyle(raw == current ? theme.palette.accent : theme.palette.fg2)
                            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(raw == current ? theme.palette.accentSoft : theme.palette.bg2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func colorRow(label: String,
                          swatches: [Color],
                          current: Color,
                          onChange: @escaping (Color) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            fieldLabel(label)
            HStack(spacing: DesignTokens.Spacing.md) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, c in
                    Button(action: { onChange(c) }) {
                        Circle()
                            .fill(c)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(c == current ? theme.palette.fg1 : .clear, lineWidth: DesignTokens.Stroke.thick))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func menuPicker(label: String,
                            values: [(String, String)],
                            current: String,
                            onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            fieldLabel(label)
            SettingsPicker(current: current) {
                ForEach(values, id: \.0) { (raw, label) in
                    Button(label) { onChange(raw) }
                }
            }
            .frame(maxWidth: 240)
        }
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.sans(11, weight: .medium))
            .foregroundStyle(theme.palette.fg3)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    AppearanceSection()
        .previewAppState(.preview)
        .frame(width: 720)
        .padding(DesignTokens.Spacing.huge)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
