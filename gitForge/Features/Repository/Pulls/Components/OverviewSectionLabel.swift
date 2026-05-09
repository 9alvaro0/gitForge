import SwiftUI

/// UPPERCASE caption label (`DESCRIPTION`, `REVIEWERS`, `LABELS`) used as the
/// header of every block inside the Overview tab.
struct OverviewSectionLabel: View {
    let text: String
    @Environment(\.appTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: FontSize.caption, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(theme.palette.fg3)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 6) {
        OverviewSectionLabel("Description")
        OverviewSectionLabel("Reviewers")
        OverviewSectionLabel("Labels")
    }
    .padding()
    .appTheme(theme)
}
