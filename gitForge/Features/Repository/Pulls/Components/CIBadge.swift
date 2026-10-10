import SwiftUI

/// CI state as glyph + word (never colour alone): ✓ passed, ✕ failed,
/// ◐ running, ◌ queued… Shared by the PR rows, the detail and the checks.
struct CIStateGlyph: View {
    enum Kind: Equatable {
        case passed, failed, running, queued, skipped, canceled, unknown
    }

    let kind: Kind
    var size: CGFloat = 13

    @Environment(\.appTheme) private var theme

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    var symbol: String {
        switch kind {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .running: "circle.lefthalf.filled"
        case .queued: "circle.dashed"
        case .skipped: "arrow.right.circle"
        case .canceled: "slash.circle"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch kind {
        case .passed: theme.colors.ok
        case .failed: theme.colors.del
        case .running: theme.colors.info
        case .queued, .skipped, .canceled, .unknown: theme.colors.textTertiary
        }
    }

    init(kind: Kind, size: CGFloat = 13) {
        self.kind = kind
        self.size = size
    }

    init(_ state: CICheck.State, size: CGFloat = 13) {
        switch state {
        case .passed: kind = .passed
        case .failed: kind = .failed
        case .running: kind = .running
        case .queued: kind = .queued
        case .skipped: kind = .skipped
        case .canceled: kind = .canceled
        }
        self.size = size
    }

    init(_ state: CIStatus.State, size: CGFloat = 13) {
        switch state {
        case .success: kind = .passed
        case .failure: kind = .failed
        case .pending: kind = .running
        case .canceled: kind = .canceled
        case .unknown: kind = .unknown
        }
        self.size = size
    }
}

/// The CI summary of a PR: glyph and label, tinted by state.
struct CIBadge: View {
    let status: CIStatus

    @Environment(\.appTheme) private var theme

    var body: some View {
        let glyph = CIStateGlyph(status.state)
        HStack(spacing: Spacing.s4) {
            glyph
            Text(status.label)
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(glyph.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CI \(status.label)")
    }
}
