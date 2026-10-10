import SwiftUI

/// "Merge blocked" / "Waiting" / "Ready to merge" with the reasons and the
/// check counts. gitForge doesn't merge PRs, so it points to the host.
struct MergeReadinessBanner: View {
    let readiness: MergeReadiness
    let hostLabel: String?

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
                Text(detail)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if readiness.passed + readiness.running + readiness.failed > 0 {
                HStack(spacing: Spacing.s12) {
                    count(readiness.passed, "passed", theme.colors.ok)
                    count(readiness.running, "running", theme.colors.info)
                    count(readiness.failed, "failed", theme.colors.del)
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
        case .blocked: "Merge blocked"
        case .waiting: "Waiting on checks or reviews"
        case .ready: "Ready to merge"
        }
    }

    private var detail: String {
        let reasons = readiness.reasons.isEmpty ? "" : readiness.reasons.joined(separator: " · ").capitalizedFirst + ". "
        return reasons + "gitForge doesn’t merge pull requests — open it on \(hostLabel ?? "the host") to merge."
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

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
