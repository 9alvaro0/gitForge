import SwiftUI

struct SegmentOption<Value: Hashable>: Identifiable {
    let id: Int
    let value: Value
    let label: String
}

/// `.gf-segmented` — small inline segmented picker matching the design.
struct SegmentedControl<Value: Hashable>: View {
    let options: [SegmentOption<Value>]
    @Binding var selection: Value

    @Environment(\.appTheme) private var theme

    init(_ rawOptions: [(Value, String)], selection: Binding<Value>) {
        var built: [SegmentOption<Value>] = []
        for (idx, raw) in rawOptions.enumerated() {
            built.append(SegmentOption(id: idx, value: raw.0, label: raw.1))
        }
        self.options = built
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { opt in
                segmentButton(opt)
            }
        }
        .padding(Spacing.s2)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.fillControl))
    }

    @ViewBuilder
    private func segmentButton(_ opt: SegmentOption<Value>) -> some View {
        let isActive = opt.value == selection
        Button(action: { selection = opt.value }) {
            Text(opt.label)
                .textRole(.callout, weight: isActive ? .semibold : .regular)
                .padding(.horizontal, Spacing.s12)
                .frame(height: 22)
                .foregroundStyle(isActive ? theme.colors.textPrimary : theme.colors.textSecondary)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: Radius.controlSmall)
                            .fill(selectedFill)
                            .shadow(color: .black.opacity(selectedShadow), radius: 1, y: 1)
                    }
                }
                .contentShape(.rect(cornerRadius: Radius.controlSmall))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Redesign spec §5: white 14 % in dark, white with a soft shadow in light.
    private var selectedFill: Color {
        theme.effectiveMode == .dark ? .white.opacity(0.14) : .white
    }
    private var selectedShadow: Double {
        theme.effectiveMode == .dark ? 0 : 0.12
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var selection: String = "all"
    VStack(spacing: DesignTokens.Spacing.xl) {
        SegmentedControl<String>([("all", "All"), ("local", "Local"), ("remote", "Remote"), ("tags", "Tags")],
                                  selection: $selection)
        Text("Selected: \(selection)").foregroundStyle(theme.palette.fg2)
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
