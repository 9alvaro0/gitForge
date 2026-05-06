import SwiftUI

/// Floating Tweaks panel ported from `tweaks-panel.jsx`. Lives in a small
/// translucent card pinned to the bottom-right corner.
struct TweaksPanel: View {
    @Environment(\.appTheme) private var theme
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if expanded {
                contentCard
                    .frame(width: 260)
            }
            toggleChip
        }
        .padding(16)
    }

    private var toggleChip: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                GFIcon(kind: .settings, size: 12, stroke: theme.palette.fg2)
                Text(expanded ? "Hide" : "Tweaks")
                    .font(AppFont.sans(11))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundStyle(theme.palette.fg2)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.palette.bg3))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.palette.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Appearance")
            radioRow(label: "Theme", values: ThemeMode.allCases.map { ($0.rawValue, $0.label) },
                     current: theme.mode.rawValue,
                     onChange: { v in if let m = ThemeMode(rawValue: v) { theme.mode = m } })

            colorRow(label: "Accent", swatches: AppTheme.accentSwatches, current: theme.accent,
                     onChange: { theme.accent = $0 })

            radioRow(label: "Density", values: Density.allCases.map { ($0.rawValue, $0.label) },
                     current: theme.density.rawValue,
                     onChange: { v in if let d = Density(rawValue: v) { theme.density = d } })

            sectionHeader("Code")
            selectRow(label: "Mono font",
                      values: MonoFontFamily.allCases.map { ($0.rawValue, $0.label) },
                      current: theme.monoFont.rawValue,
                      onChange: { v in if let f = MonoFontFamily(rawValue: v) { theme.monoFont = f } })
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.palette.lineStrong, lineWidth: 1))
        .shadow(color: theme.palette.shadowColor, radius: 22, y: 10)
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(theme.palette.fg3)
    }

    @ViewBuilder
    private func radioRow(label: String, values: [(String, String)], current: String, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(AppFont.sans(11)).foregroundStyle(theme.palette.fg3)
            HStack(spacing: 4) {
                ForEach(values, id: \.0) { (raw, label) in
                    Button(action: { onChange(raw) }) {
                        Text(label.capitalized)
                            .font(AppFont.sans(11))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .foregroundStyle(raw == current ? theme.palette.accent : theme.palette.fg2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(raw == current ? theme.palette.accentSoft : theme.palette.bg3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func colorRow(label: String, swatches: [Color], current: Color, onChange: @escaping (Color) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(AppFont.sans(11)).foregroundStyle(theme.palette.fg3)
            HStack(spacing: 6) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, c in
                    Button(action: { onChange(c) }) {
                        Circle()
                            .fill(c)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(c == current ? theme.palette.fg1 : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func selectRow(label: String, values: [(String, String)], current: String, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(AppFont.sans(11)).foregroundStyle(theme.palette.fg3)
            Menu {
                ForEach(values, id: \.0) { (raw, label) in
                    Button(label) { onChange(raw) }
                }
            } label: {
                HStack {
                    Text(current).font(AppFont.sans(12))
                    Spacer()
                    GFIcon(kind: .chevD, size: 10, stroke: theme.palette.fg3)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .foregroundStyle(theme.palette.fg1)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.palette.bg3))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.palette.lineStrong, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    TweaksPanel()
        .frame(width: 360, height: 480, alignment: .bottomTrailing)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
