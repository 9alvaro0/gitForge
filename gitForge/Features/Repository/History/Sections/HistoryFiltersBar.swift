import SwiftUI

struct HistoryFiltersBar: View {
    @Binding var search: String
    let totalCount: Int
    let matchCount: Int

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            GFTextField(placeholder: "Search subject, author, sha…", text: $search)
                .frame(maxWidth: 320)
            Spacer()
            MonoText(summary, dim: true)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
    }

    private var summary: String {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "\(totalCount) commits"
        }
        return "\(matchCount) of \(totalCount) match"
    }
}

#Preview("Empty search") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var search = ""
    HistoryFiltersBar(search: $search, totalCount: 124, matchCount: 124)
        .frame(width: 1100)
        .appTheme(theme)
}

#Preview("With search") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var search = "feat:"
    HistoryFiltersBar(search: $search, totalCount: 124, matchCount: 17)
        .frame(width: 1100)
        .appTheme(theme)
}
