import SwiftUI

/// Shared by skeleton, unified, and split so the hunk strip stays in sync
/// wherever it appears. In Changes it also carries the hunk's stage /
/// unstage / discard buttons.
struct DiffHunkHeader: View {
    let hunk: DiffHunk
    var controls: Controls? = nil

    /// The hunk's actions, already titled for the current line selection.
    struct Controls {
        let applyTitle: String
        let onApply: () -> Void
        /// Unstaged side only.
        var discardTitle: String? = nil
        var onDiscard: (() -> Void)? = nil
        var disabled = false
    }

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s6) {
            Text(hunk.header.isEmpty ? "@@" : hunk.header)
                .font(AppFont.font(.mono, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textQuaternary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let controls {
                if let discardTitle = controls.discardTitle, let onDiscard = controls.onDiscard {
                    GFButton(title: discardTitle, style: .destructive, size: .small,
                             disabled: controls.disabled, action: onDiscard)
                }
                GFButton(title: controls.applyTitle, size: .small, disabled: controls.disabled,
                         action: controls.onApply)
            }
        }
        .padding(.horizontal, Spacing.s12)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(theme.colors.info.opacity(0.07))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 0) {
        DiffHunkHeader(hunk: DiffHunk.previewSamples[0])
        DiffHunkHeader(hunk: DiffHunk.previewSamples[0],
                       controls: .init(applyTitle: "Stage hunk", onApply: {},
                                       discardTitle: "Discard hunk…", onDiscard: {}))
    }
    .frame(width: 520)
    .appTheme(theme)
}
