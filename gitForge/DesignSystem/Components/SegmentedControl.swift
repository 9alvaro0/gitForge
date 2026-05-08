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
        HStack(spacing: DesignTokens.Spacing.none) {
            ForEach(options) { opt in
                segmentButton(opt)
            }
        }
        .padding(DesignTokens.Spacing.xxs)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    @ViewBuilder
    private func segmentButton(_ opt: SegmentOption<Value>) -> some View {
        let isActive = opt.value == selection
        Button(action: { selection = opt.value }) {
            Text(opt.label)
                .font(AppFont.sans(11))
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .frame(height: 22)
                .foregroundStyle(isActive ? theme.palette.fg1 : theme.palette.fg3)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(isActive ? theme.palette.bg5 : .clear)
                )
                .contentShape(.rect(cornerRadius: DesignTokens.Radius.xs))
        }
        .buttonStyle(.plain)
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
