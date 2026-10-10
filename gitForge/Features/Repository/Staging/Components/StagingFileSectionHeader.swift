import SwiftUI

/// Header above the Unstaged / Staged blocks: select-all checkbox, title with
/// count, and the section-wide action. Checkbox and action are optional so
/// the loading skeleton can reuse the header without live controls.
struct StagingFileSectionHeader: View {
    let title: String
    let count: Int
    var selection: StagingSectionSelection? = nil
    var onToggleAll: (() -> Void)? = nil
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s8) {
            if let selection, let onToggleAll, count > 0 {
                Button(action: onToggleAll) {
                    GFCheckboxBox(state: boxState(selection))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select all \(title.lowercased())")
                .accessibilityValue(spokenValue(selection))
            }
            Text("\(title) · \(count)")
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.textQuaternary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionLabel, let onAction {
                GFButton(title: actionLabel, size: .small, disabled: count == 0, action: onAction)
            }
        }
        .padding(.horizontal, Spacing.s8)
        .frame(height: 30)
    }

    private func boxState(_ selection: StagingSectionSelection) -> GFCheckboxBox.State {
        switch selection {
        case .empty: .off
        case .partial: .mixed
        case .full: .on
        }
    }

    private func spokenValue(_ selection: StagingSectionSelection) -> String {
        switch selection {
        case .empty: "none selected"
        case .partial(let n): "\(n) of \(count) selected"
        case .full: "all selected"
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 0) {
        StagingFileSectionHeader(title: "Unstaged", count: 7, selection: .partial(2), onToggleAll: {},
                                 actionLabel: "Stage all", onAction: {})
        StagingFileSectionHeader(title: "Staged", count: 3, selection: .empty, onToggleAll: {},
                                 actionLabel: "Unstage all", onAction: {})
        StagingFileSectionHeader(title: "Staged", count: 0)
    }
    .frame(width: 400)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
