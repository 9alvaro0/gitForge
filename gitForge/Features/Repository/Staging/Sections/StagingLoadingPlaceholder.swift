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
        LazyVStack(spacing: 0) {
            StagingFileSectionHeader(title: "Unstaged", count: 0)
            ForEach(0..<3, id: \.self) { index in
                row(index: index)
            }
            StagingFileSectionHeader(title: "Staged", count: 0)
                .padding(.top, Spacing.s12)
            ForEach(3..<5, id: \.self) { index in
                row(index: index)
            }
        }
        .skeleton(true)
    }

    private func row(index: Int) -> some View {
        HStack(spacing: Spacing.s8) {
            GFCheckboxBox(state: .off)
            StatusTag(kind: .modified)
            Text(Self.placeholderPaths[index % Self.placeholderPaths.count])
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Spacing.s8)
        .padding(.trailing, Spacing.s12)
        .frame(height: theme.density.metrics.rowList)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    StagingLoadingPlaceholder()
        .frame(width: 440, height: 360)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
