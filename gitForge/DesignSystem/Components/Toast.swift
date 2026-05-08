import SwiftUI

struct ToastMessage: Equatable, Identifiable {
    enum Kind { case info, ok, warn, error }
    let id = UUID()
    var message: String
    var kind: Kind = .ok
}

struct ToastView: View {
    let toast: ToastMessage
    var onDismiss: () -> Void = {}

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            GFIcon(kind: icon, size: 14, stroke: iconColor)
            Text(toast.message)
                .font(AppFont.sans(12.5))
                .foregroundStyle(theme.palette.fg1)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg3))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.lineStrong, lineWidth: 1))
        .shadow(color: theme.palette.shadowColor, radius: 20, y: 8)
        .onTapGesture { onDismiss() }
    }

    private var icon: GFIconKind {
        switch toast.kind {
        case .ok:    return .check
        case .info:  return .dot
        case .warn:  return .warn
        case .error: return .x
        }
    }
    private var iconColor: Color {
        switch toast.kind {
        case .ok:    return theme.palette.ok
        case .info:  return theme.palette.info
        case .warn:  return theme.palette.warn
        case .error: return theme.palette.del
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: DesignTokens.Spacing.xl) {
        ToastView(toast: .previewOk)
        ToastView(toast: .previewInfo)
        ToastView(toast: .previewWarn)
        ToastView(toast: .previewError)
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
#endif
