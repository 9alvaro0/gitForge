import SwiftUI

/// Unchanged lines a diff hides between hunks: a "Show N hidden lines" row
/// until it's clicked, then the lines themselves as context.
struct DiffGapSection: View {
    let gap: DiffGap
    let isExpanded: Bool
    /// New side of the file (`DiffGap.lines(from:)`).
    let fileLines: [String]
    /// Render as split-view rows (the same line on both sides).
    var split = false
    let onExpand: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(gap.lines(from: fileLines)) { line in
                    if split {
                        HStack(alignment: .top, spacing: 0) {
                            DiffSplitCell(line: line, side: .left, attributed: nil)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            Rectangle().fill(theme.colors.separator).frame(width: 1)
                            DiffSplitCell(line: line, side: .right, attributed: nil)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        DiffRow(line: line, attributed: nil)
                    }
                }
            }
        } else {
            Button(action: onExpand) {
                HStack(spacing: Spacing.s6) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text(gap.count == 1 ? String(localized: "Show 1 hidden line") : String(localized: "Show \(gap.count) hidden lines"))
                        .textRole(.caption)
                }
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, Spacing.s12)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .background(theme.colors.fillControl.opacity(0.5))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Show the unchanged lines between these changes")
        }
    }
}
