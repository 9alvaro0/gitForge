import SwiftUI

/// Live preview for the Appearance step: a History header and seven sample
/// commits with lanes, a branch chip and a selected row, drawn with the
/// current theme, density and code font.
struct AppearancePreview: View {
    @Environment(\.appTheme) private var theme

    private struct Sample: Identifiable {
        let id: Int
        let subject: String
        let sha: String
        let chip: String?
        let lane: LaneColors.Assignment
    }

    private static let samples: [Sample] = [
        Sample(id: 0, subject: "Render lanes through the graph renderer", sha: "a91f3c2", chip: "graph-renderer", lane: .accent),
        Sample(id: 1, subject: "Extract the lane layout engine", sha: "7c04e1d", chip: nil, lane: .accent),
        Sample(id: 2, subject: "Merge pull request #214", sha: "e2b8d90", chip: nil, lane: .lane(.lane0)),
        Sample(id: 3, subject: "Add a graph renderer protocol", sha: "3f6a2bb", chip: nil, lane: .accent),
        Sample(id: 4, subject: "Bump swift-syntax to 600.0.1", sha: "b19c4e7", chip: nil, lane: .lane(.lane0)),
        Sample(id: 5, subject: "Hunk-level ours / theirs / both picker", sha: "fe1290a", chip: nil, lane: .lane(.lane3)),
        Sample(id: 6, subject: "Release 1.3.2", sha: "4ab7e31", chip: nil, lane: .lane(.lane0)),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History").textRole(.body, weight: .semibold)
                Spacer()
                Text("Push 2")
                    .textRole(.caption, weight: .semibold)
                    .foregroundStyle(theme.colors.accentOnFill)
                    .padding(.horizontal, Spacing.s8)
                    .frame(height: 22)
                    .background(Capsule().fill(theme.colors.accentFill))
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 40)
            Divider().overlay(theme.colors.separator)
            VStack(spacing: 0) {
                ForEach(Self.samples) { sample in row(sample) }
            }
            .padding(Spacing.s6)
        }
        .foregroundStyle(theme.colors.textPrimary)
        .background(RoundedRectangle(cornerRadius: Radius.panel).fill(theme.colors.bgContent))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(theme.colors.separator, lineWidth: 1))
        .shadow(color: theme.colors.shadow, radius: 30, y: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of History with the chosen look")
    }

    private func row(_ sample: Sample) -> some View {
        let color = LaneColors.color(sample.lane, dark: theme.effectiveMode == .dark, accent: theme.colors.accent)
        return HStack(spacing: Spacing.s8) {
            ZStack {
                Rectangle().fill(color).frame(width: 2)
                Circle().fill(color).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(theme.colors.bgContent, lineWidth: 2))
            }
            .frame(width: 28)
            if let chip = sample.chip {
                Text(chip)
                    .textRole(.monoSmall, weight: .semibold)
                    .foregroundStyle(theme.colors.accent)
                    .padding(.horizontal, Spacing.s6)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: Radius.chip).fill(theme.colors.accentSoft))
            }
            Text(sample.subject).textRole(.body).lineLimit(1)
            Spacer(minLength: Spacing.s8)
            Text(sample.sha).textRole(.monoSmall).foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.trailing, Spacing.s8)
        .frame(height: theme.density.metrics.rowList)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(sample.id == 3 ? theme.colors.accentSoft : .clear))
    }
}
