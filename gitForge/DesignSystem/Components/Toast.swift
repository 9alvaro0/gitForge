import SwiftUI

struct ToastMessage: Equatable, Identifiable {
    enum Kind { case info, ok, warn, error }
    let id = UUID()
    var message: String
    var kind: Kind = .ok

    /// Redesign spec §5: toasts leave after 4 s, errors stay until dismissed.
    var autoDismissAfter: Duration? {
        kind == .error ? nil : .seconds(4)
    }
}

/// Bottom-centre glass toast (redesign spec §5): shape-coded glyph plus
/// message. Click dismisses it.
struct ToastView: View {
    let toast: ToastMessage
    var onDismiss: () -> Void = {}

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(toast.message)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.vertical, Spacing.s8)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.popover))
        .shadow(color: theme.colors.shadow, radius: 15, y: 10)
        .contentShape(.rect(cornerRadius: Radius.popover))
        .onTapGesture { onDismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityAction(named: "Dismiss") { onDismiss() }
    }

    /// Glyphs differ in shape, not just colour.
    private var symbol: String {
        switch toast.kind {
        case .ok:    "checkmark.circle.fill"
        case .info:  "info.circle.fill"
        case .warn:  "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch toast.kind {
        case .ok:    theme.colors.ok
        case .info:  theme.colors.info
        case .warn:  theme.colors.warn
        case .error: theme.colors.del
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: Spacing.s12) {
        ToastView(toast: .previewOk)
        ToastView(toast: .previewInfo)
        ToastView(toast: .previewWarn)
        ToastView(toast: .previewError)
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
