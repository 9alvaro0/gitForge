import SwiftUI

/// The only section that uses a two-column layout — visual choices
/// (theme/accent/density) sit alongside code-display ones (font, diff
/// view, context, wrap, dates) so the eye scans them in pairs.
struct AppearanceSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(WorkspaceUI.self) private var ui

    var body: some View {
        SettingsSection(title: String(localized: "Appearance")) {
            HStack(alignment: .top, spacing: Spacing.s24) {
                appearanceColumn
                codeColumn
            }
            .padding(.horizontal, Spacing.s12)
            .padding(.vertical, Spacing.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appearanceColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            radioRow(label: String(localized: "Theme"),
                     values: ThemeMode.allCases.map { ($0.rawValue, $0.label) },
                     current: ui.theme.mode.rawValue) { v in
                if let m = ThemeMode(rawValue: v) { ui.theme.mode = m }
            }
            colorRow(label: String(localized: "Accent"),
                     swatches: AppTheme.accentSwatches,
                     current: ui.theme.accent) { ui.theme.accent = $0 }
            radioRow(label: String(localized: "Density"),
                     values: Density.allCases.map { ($0.rawValue, $0.label) },
                     current: ui.theme.density.rawValue) { v in
                if let d = Density(rawValue: v) { ui.theme.density = d }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var codeColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            menuPicker(label: String(localized: "Mono font"),
                       values: MonoFontFamily.availableCases.map { ($0.rawValue, $0.label) },
                       current: ui.theme.monoFont.resolved().rawValue) { v in
                if let f = MonoFontFamily(rawValue: v) { ui.theme.monoFont = f }
            }
            radioRow(label: String(localized: "Diff view"),
                     values: DiffPane.ViewMode.allCases.map { ($0.rawValue, $0.label) },
                     current: ui.preferences.defaultDiffMode.rawValue) { v in
                if let m = DiffPane.ViewMode(rawValue: v) { ui.preferences.defaultDiffMode = m }
            }
            menuPicker(label: String(localized: "Diff context lines"),
                       values: Self.contextOptions,
                       current: String(ui.preferences.diffContextLines)) { v in
                if let n = Int(v) { ui.preferences.diffContextLines = n }
            }
            wrapToggle
            radioRow(label: String(localized: "Dates"),
                     values: DateDisplayMode.allCases.map { ($0.rawValue, $0.label) },
                     current: ui.preferences.dateDisplayMode.rawValue) { v in
                if let m = DateDisplayMode(rawValue: v) { ui.preferences.dateDisplayMode = m }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wrapToggle: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            fieldLabel(String(localized: "Wrap long diff lines"))
            Toggle(isOn: Binding(
                get: { ui.preferences.diffWrapLongLines },
                set: { ui.preferences.diffWrapLongLines = $0 }
            )) {
                Text(ui.preferences.diffWrapLongLines ? String(localized: "Soft-wrap onto the next visual row") : String(localized: "Overflow horizontally (default)"))
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private static let contextOptions: [(String, String)] = [
        ("1", String(localized: "1 line")), ("3", String(localized: "3 lines")),
        ("5", String(localized: "5 lines")), ("10", String(localized: "10 lines")),
    ]

    @ViewBuilder
    private func radioRow(label: String,
                          values: [(String, String)],
                          current: String,
                          onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            fieldLabel(label)
            // Options that don't fit the column go on the next line rather
            // than being cut ("Absolute (2026-05-09 14:32)" is wide).
            FlowLayout(spacing: Spacing.s4, fitsWideItems: true) {
                ForEach(values, id: \.0) { (raw, label) in
                    Button(action: { onChange(raw) }) {
                        Text(label.capitalized)
                            .textRole(.callout)
                            .lineLimit(1)
                            .padding(.horizontal, Spacing.s12)
                            .frame(height: 24)
                            .foregroundStyle(raw == current ? theme.colors.accent : theme.colors.textSecondary)
                            .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(raw == current ? theme.colors.accentSoft : theme.colors.bgContent))
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
        VStack(alignment: .leading, spacing: Spacing.s6) {
            fieldLabel(label)
            HStack(spacing: Spacing.s8) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, c in
                    Button(action: { onChange(c) }) {
                        Circle()
                            .fill(c)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(c == current ? theme.colors.textPrimary : .clear, lineWidth: 2))
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
        VStack(alignment: .leading, spacing: Spacing.s6) {
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
            .textRole(.callout, weight: .medium)
            .foregroundStyle(theme.colors.textTertiary)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    AppearanceSection()
        .previewAppState(.preview)
        .frame(width: 720)
        .padding(Spacing.s20)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
