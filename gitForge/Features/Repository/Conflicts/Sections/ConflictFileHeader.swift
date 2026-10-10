import SwiftUI

/// Top of the selected file: its path and progress, the whole-file actions
/// (take one side for every hunk), and Mark resolved.
struct ConflictFileHeader: View {
    let path: String
    let hunkCount: Int
    let pickedCount: Int
    /// The result is being written by hand instead of with picks.
    let isManual: Bool
    let canMarkResolved: Bool
    let currentBranchName: String?
    let onTakeOurs: () -> Void
    let onTakeTheirs: () -> Void
    let onOpenInEditor: () -> Void
    let onMarkResolved: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s8) {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(path)
                        .font(AppFont.font(.mono, weight: .semibold, monoFamily: theme.monoFont))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    if isManual {
                        Text("Resolving by hand")
                            .textRole(.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                    } else {
                        HStack(spacing: Spacing.s6) {
                            ConflictProgressBar(done: pickedCount, total: hunkCount, width: 60)
                            Text("\(pickedCount) of \(hunkCount) hunks picked")
                                .textRole(.caption)
                                .foregroundStyle(theme.colors.textTertiary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The buttons keep their size; the path truncates instead.
                Group {
                    ConflictSideButton(side: .ours, title: "Take ours", action: onTakeOurs)
                        .help("Resolve the whole file with ours and mark it resolved")
                    ConflictSideButton(side: .theirs, title: "Take theirs", action: onTakeTheirs)
                        .help("Resolve the whole file with theirs and mark it resolved")
                    IconButton(.ext, accessibilityLabel: "Open in editor", action: onOpenInEditor)
                        .help("Open in editor")
                    GFButton(title: "Mark resolved", style: .primary,
                             disabled: !canMarkResolved, action: onMarkResolved)
                        .help(isManual ? "Write your result to the file and stage it" : "Write the picks to the file and stage it")
                }
                .fixedSize()
            }
            .padding(.horizontal, Spacing.s16)
            .frame(height: 52)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.colors.separator).frame(height: 1)
            }
            sidesStrip
        }
    }

    /// Which side is which, with the arrow that the buttons and lines reuse.
    private var sidesStrip: some View {
        HStack(spacing: 0) {
            sideLabel(.ours, detail: currentBranchName ?? "HEAD")
            Rectangle().fill(theme.colors.separator).frame(width: 1)
            sideLabel(.theirs, detail: "incoming")
        }
        .frame(height: 30)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
    }

    private func sideLabel(_ side: ConflictSide, detail: String) -> some View {
        HStack(spacing: Spacing.s8) {
            Text(side.label)
                .font(AppFont.font(.monoSmall, weight: .bold, monoFamily: theme.monoFont))
                .foregroundStyle(theme.variant.isDark ? Color(hex: 0x101014) : .white)
                .padding(.horizontal, Spacing.s6)
                .background(RoundedRectangle(cornerRadius: Radius.badge).fill(side.color(theme.colors)))
            Text(detail)
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(side.soft(theme.colors).opacity(0.5))
    }
}
