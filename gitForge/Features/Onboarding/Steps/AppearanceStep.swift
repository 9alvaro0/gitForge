import SwiftUI

/// "Make it yours" (artboard `Onboarding`): appearance, accent, density and
/// code font, applied live to the app theme, beside a preview of History.
struct AppearanceStep: View {
    @Environment(WorkspaceUI.self) private var ui
    @Environment(\.appTheme) private var theme

    var body: some View {
        // Side by side when there's room; the preview goes below otherwise.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.s48) {
                controls.frame(minWidth: 420, alignment: .leading)
                AppearancePreview().frame(width: 420)
            }
            VStack(alignment: .leading, spacing: Spacing.s24) {
                controls
                AppearancePreview().frame(maxWidth: 480)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Spacing.s24) {
            appearance
            accent
            HStack(alignment: .top, spacing: Spacing.s24) {
                density
                codeFont
            }
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        group("Appearance") {
            HStack(spacing: Spacing.s12) {
                ForEach([ThemeMode.light, .dark, .system]) { mode in
                    themeCard(mode)
                }
            }
            Text("Follows “Increase contrast” in System Settings.")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private func themeCard(_ mode: ThemeMode) -> some View {
        let selected = ui.theme.mode == mode
        return Button { ui.theme.mode = mode } label: {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                ThemeThumbnail(mode: mode, accent: theme.colors.accent)
                    .frame(height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.row))
                Text(mode == .system ? "Match system" : mode.label)
                    .textRole(.callout, weight: selected ? .semibold : .regular)
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.horizontal, Spacing.s2)
            }
            .padding(Spacing.s8)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.fillControl))
            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(selected ? theme.colors.accent : theme.colors.separator, lineWidth: selected ? 2 : 1))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Accent

    private var accent: some View {
        group("Accent") {
            HStack(spacing: Spacing.s12) {
                ForEach(Array(AccentSwatch.allCases.enumerated()), id: \.offset) { _, swatch in
                    swatchButton(swatch)
                }
            }
        }
    }

    private func swatchButton(_ swatch: AccentSwatch) -> some View {
        let selected = ui.theme.accentSwatch == swatch
        return Button { ui.theme.accent = Color(hex: swatch.swatch) } label: {
            VStack(spacing: Spacing.s6) {
                Circle()
                    .fill(Color(hex: swatch.swatch))
                    .frame(width: 36, height: 36)
                    .overlay {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: swatch.onFill))
                        }
                    }
                    .padding(3)
                    .overlay(Circle().strokeBorder(selected ? Color(hex: swatch.swatch) : .clear, lineWidth: 2))
                Text(Self.name(swatch))
                    .textRole(.caption)
                    .foregroundStyle(selected ? theme.colors.textPrimary : theme.colors.textSecondary)
            }
            .frame(width: 64)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(swatch))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func name(_ swatch: AccentSwatch) -> String {
        switch swatch {
        case .violet: "Violet"
        case .green: "Green"
        case .coral: "Coral"
        case .blue: "Blue"
        }
    }

    // MARK: Density and code font

    private var density: some View {
        @Bindable var themeModel = ui.theme
        return group("Density") {
            Picker("Density", selection: $themeModel.density) {
                Text("Regular").tag(Density.regular)
                Text("Compact").tag(Density.compact)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(ui.theme.density == .regular
                 ? "\(Int(Density.regular.metrics.rowList)) pt rows · comfortable for long sessions"
                 : "\(Int(Density.compact.metrics.rowList)) pt rows · more commits on screen")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var codeFont: some View {
        @Bindable var themeModel = ui.theme
        let fonts = MonoFontFamily.availableCases
        return group("Code font") {
            if fonts.count <= 3 {
                Picker("Code font", selection: $themeModel.monoFont) {
                    ForEach(fonts, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } else {
                Picker("Code font", selection: $themeModel.monoFont) {
                    ForEach(fonts, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }
            Text("Used for hashes, paths and diffs.")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Text(title)
                .textRole(.body, weight: .semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// A tiny window drawing for the theme cards: sidebar, two text lines and
/// an accent line, in light, dark or half and half.
private struct ThemeThumbnail: View {
    let mode: ThemeMode
    let accent: Color

    var body: some View {
        switch mode {
        case .light: window(dark: false)
        case .dark: window(dark: true)
        case .system:
            HStack(spacing: 0) { window(dark: false); window(dark: true) }
        }
    }

    private func window(dark: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(dark ? Color(hex: 0x2A2A32) : Color(hex: 0xECECF1)).frame(maxWidth: 28)
            VStack(alignment: .leading, spacing: 6) {
                line(dark, 0.7)
                line(dark, 0.5)
                Capsule().fill(accent).frame(height: 6).frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: 0.6, anchor: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(dark ? Color(hex: 0x18181C) : Color.white)
        }
        .accessibilityHidden(true)
    }

    private func line(_ dark: Bool, _ fraction: CGFloat) -> some View {
        Capsule()
            .fill(dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
            .frame(height: 6)
            .scaleEffect(x: fraction, anchor: .leading)
    }
}
