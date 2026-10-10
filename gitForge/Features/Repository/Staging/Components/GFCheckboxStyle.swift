import SwiftUI

/// The 14 pt checkbox shared by the file rows and the select-all box:
/// accent fill when on, a dash when only part of a section is ticked.
struct GFCheckboxBox: View {
    enum State { case off, on, mixed }

    let state: State

    @Environment(\.appTheme) private var theme

    var body: some View {
        let filled = state != .off
        ZStack {
            RoundedRectangle(cornerRadius: Radius.badge)
                .fill(filled ? theme.colors.accentFill : theme.colors.bgContent)
            RoundedRectangle(cornerRadius: Radius.badge)
                .strokeBorder(filled ? theme.colors.accentFill : theme.colors.strokeControl, lineWidth: 1)
            switch state {
            case .on:
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(theme.colors.accentOnFill)
            case .mixed:
                Capsule()
                    .fill(theme.colors.accentOnFill)
                    .frame(width: 7, height: 2)
            case .off:
                EmptyView()
            }
        }
        .frame(width: 14, height: 14)
        .contentShape(.rect)
    }
}

struct GFCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            GFCheckboxBox(state: configuration.isOn ? .on : .off)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var on = true
    @Previewable @State var off = false
    HStack(spacing: 16) {
        Toggle("", isOn: $on).toggleStyle(GFCheckboxStyle())
        Toggle("", isOn: $off).toggleStyle(GFCheckboxStyle())
        GFCheckboxBox(state: .mixed)
    }
    .padding()
    .appTheme(theme)
}
