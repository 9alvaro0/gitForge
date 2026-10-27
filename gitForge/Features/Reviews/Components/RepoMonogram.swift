import SwiftUI

/// A repo's mark in Team and Mine: its initials on a soft square in a colour
/// of its own, the same every time, so a project is told apart at a glance.
struct RepoMonogram: View {
    let repo: RemoteHost
    var size: CGFloat = 26

    @Environment(\.appTheme) private var theme

    var body: some View {
        let color = LaneColors.color(.lane(Self.lane(for: repo.id)), dark: theme.variant.isDark,
                                     accent: theme.colors.accent)
        Text(Self.initials(for: repo.repo))
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(color.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(color.opacity(0.32), lineWidth: 1))
            .accessibilityHidden(true)
    }

    /// One letter per word of the name, two at most: `payments-app` is PA,
    /// `ledger` is L. Digits count as letters; other characters split words.
    nonisolated static func initials(for name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        let letters = words.prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// The repo's colour, by its key: stable across launches.
    nonisolated static func lane(for key: String) -> LaneColors.Lane {
        let lanes = LaneColors.Lane.allCases
        var hash: UInt = 0
        for scalar in key.unicodeScalars { hash = (hash &* 31) &+ UInt(scalar.value) }
        return lanes[Int(hash % UInt(lanes.count))]
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
    HStack(spacing: Spacing.s8) {
        ForEach(["apps/payments/android/payments-app", "apps/platform/infra-modules", "oss/ledger", "x/r2-d2"], id: \.self) {
            RepoMonogram(repo: RemoteHost.make(fullName: $0, on: instance)!)
        }
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
