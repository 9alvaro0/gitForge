import SwiftUI

/// The What's New sheet: each highlight with its symbol, title and one
/// sentence, then the fixes and improvements in a small "And also" block.
struct WhatsNewSheet: View {
    let presentation: WhatsNewPresentation
    /// Language of the notes; the app's own by default.
    var language: String = WhatsNewCatalog.preferredLanguage()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var contentHeight: CGFloat = 0

    private static let width: CGFloat = 520
    /// Taller content scrolls instead of growing the sheet.
    private static let maxContentHeight: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, Self.maxContentHeight))

            Rectangle()
                .fill(theme.colors.separator)
                .frame(height: 1)

            footer
        }
        .frame(width: Self.width)
        .onExitCommand { dismiss() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.s20) {
            header
            groups
            if !presentation.alsoItems.isEmpty {
                alsoBlock
            }
        }
        .padding(.horizontal, Spacing.s24)
        .padding(.top, Spacing.s24)
        .padding(.bottom, Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text("What's New")
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.accent)
            Text(verbatim: "gitForge \(presentation.currentVersion)")
                .textRole(.title)
                .foregroundStyle(theme.colors.textPrimary)
            if let previous = presentation.previousVersion {
                Text("Updated from \(previous)")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// One group per release when several are shown, with its version on top.
    @ViewBuilder
    private var groups: some View {
        let releases = presentation.highlightGroups
        VStack(alignment: .leading, spacing: Spacing.s24) {
            ForEach(releases) { release in
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    if releases.count > 1 {
                        Text(verbatim: release.version)
                            .textRole(.caption, weight: .semibold)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    ForEach(release.highlights.indices, id: \.self) { index in
                        WhatsNewHighlightRow(highlight: release.highlights[index], language: language)
                    }
                }
            }
        }
    }

    private var alsoBlock: some View {
        Text(alsoText)
            .textRole(.callout)
            .foregroundStyle(theme.colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s12)
            .background(theme.colors.fillControl, in: .rect(cornerRadius: Radius.control))
    }

    /// "And also:" in the secondary colour, then every fix and improvement.
    private var alsoText: AttributedString {
        var lead = AttributedString(String(localized: "And also:"))
        lead.inlinePresentationIntent = .stronglyEmphasized
        lead.foregroundColor = theme.colors.textSecondary
        let items = presentation.alsoItems.map { $0.resolved(for: language) }
        return lead + AttributedString(" " + items.joined(separator: " "))
    }

    private var footer: some View {
        HStack {
            Link("Release notes on the web", destination: presentation.releaseNotesURL)
                .textRole(.callout)
                .foregroundStyle(theme.colors.accent)
            Spacer()
            GFButton(title: String(localized: "Continue"), style: .primary, shortcut: .defaultAction) {
                dismiss()
            }
        }
        // Same inset as the content, so the link lines up with the text above.
        .padding(.horizontal, Spacing.s24)
        .padding(.vertical, Spacing.s12)
    }
}

/// A highlight: symbol tile, title and one sentence.
private struct WhatsNewHighlightRow: View {
    let highlight: WhatsNewHighlight
    let language: String

    @Environment(\.appTheme) private var theme

    private static let tileSize: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s12) {
            tile
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(highlight.title.resolved(for: language))
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(highlight.body.resolved(for: language))
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return Image(systemName: highlight.resolvedSymbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(theme.colors.accent)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .background(theme.colors.accentSoft, in: shape)
            // High contrast outlines soft fills (redesign spec §4.1).
            .overlay {
                shape.strokeBorder(theme.colors.accent, lineWidth: 1)
                    .opacity(theme.increasedContrast ? 1 : 0)
            }
            .accessibilityHidden(true)
    }
}

#Preview("One release") {
    WhatsNewSheetPreview(presentation: .previewSingle)
}

#Preview("Several releases") {
    WhatsNewSheetPreview(presentation: .previewAccumulated)
}

#Preview("No fixes, light") {
    WhatsNewSheetPreview(presentation: .previewNoExtras, scheme: .light)
}

/// Gives a preview its own theme in the requested appearance.
private struct WhatsNewSheetPreview: View {
    let presentation: WhatsNewPresentation
    var scheme: ColorScheme = .dark

    @State private var theme = AppTheme()

    var body: some View {
        WhatsNewSheet(presentation: presentation, language: "es")
            .background(theme.colors.bgElevated)
            .appTheme(theme)
            .preferredColorScheme(scheme)
            .onAppear { theme.systemColorScheme = scheme }
    }
}
