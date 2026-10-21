import SwiftUI

/// "Merge blocked" / "Waiting" / "Ready to merge" with the host's reasons
/// and the check counts.
struct MergeReadinessBanner: View {
    let readiness: MergeReadiness

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(title)
                    .textRole(.body, weight: .semibold)
                    .foregroundStyle(tint)
                if let summary = readiness.summary {
                    Text(summary)
                        .textRole(.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if readiness.passed + readiness.running + readiness.failed > 0 {
                HStack(spacing: Spacing.s12) {
                    count(readiness.passed, String(localized: "checks.count.passed", defaultValue: "passed"), theme.colors.ok)
                    count(readiness.running, String(localized: "checks.count.running", defaultValue: "running"), theme.colors.info)
                    count(readiness.failed, String(localized: "checks.count.failed", defaultValue: "failed"), theme.colors.del)
                }
                .fixedSize()
            }
        }
        .padding(Spacing.s12)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(soft))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(tint.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func count(_ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: Spacing.s4) {
            Text("\(n)").textRole(.callout, weight: .bold).foregroundStyle(color)
            Text(label).textRole(.callout).foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var title: String {
        switch readiness.kind {
        case .blocked: String(localized: "Merge blocked")
        case .waiting: String(localized: "Waiting on checks or reviews")
        case .ready: String(localized: "Ready to merge")
        }
    }

    private var symbol: String {
        switch readiness.kind {
        case .blocked: "xmark.octagon.fill"
        case .waiting: "clock.fill"
        case .ready: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch readiness.kind {
        case .blocked: theme.colors.del
        case .waiting: theme.colors.info
        case .ready: theme.colors.ok
        }
    }

    private var soft: Color {
        switch readiness.kind {
        case .blocked: theme.colors.delSoft
        case .waiting: theme.colors.infoSoft
        case .ready: theme.colors.okSoft
        }
    }
}
