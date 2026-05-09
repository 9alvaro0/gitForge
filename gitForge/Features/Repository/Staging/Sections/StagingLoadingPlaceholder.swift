import SwiftUI

/// Skeleton list shown while the working copy hasn't finished its first
/// refresh. Sample paths keep the layout realistic so the user perceives
/// loading, not a blank state.
struct StagingLoadingPlaceholder: View {
    @Environment(\.appTheme) private var theme

    private static let placeholderPaths = [
        "Sources/Features/Repository/Staging/StagingView.swift",
        "Sources/Core/Git/GitCLI.swift",
        "Sources/Core/Models/WorkingCopyFile.swift",
        "Sources/DesignSystem/Components/Skeleton.swift",
        "README.md",
    ]

    var body: some View {
        LazyVStack(spacing: DesignTokens.Spacing.none) {
            StagingFileSectionHeader(title: "Staged", count: 0)
            ForEach(0..<2, id: \.self) { index in
                row(index: index)
            }
            Divider().background(theme.palette.line)
            StagingFileSectionHeader(title: "Unstaged", count: 0)
            ForEach(2..<5, id: \.self) { index in
                row(index: index)
            }
        }
        .skeleton(true)
    }

    @ViewBuilder
    private func row(index: Int) -> some View {
        let path = Self.placeholderPaths[index % Self.placeholderPaths.count]
        HStack(spacing: DesignTokens.Spacing.md) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                .fill(theme.palette.bg2)
                .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
            StatusTag(kind: .modified)
            Text(path)
                .font(AppFont.mono(11.5, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg2)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(height: DesignTokens.IconSize.huge)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    StagingLoadingPlaceholder()
        .frame(width: 380, height: 360)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
