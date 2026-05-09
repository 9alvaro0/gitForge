import Foundation

/// User-facing presentation style for `Date` values across History, Pulls,
/// Branches, and Commit detail. Persisted via `AppTheme.dateDisplayMode`.
nonisolated enum DateDisplayMode: String, CaseIterable, Identifiable, Sendable {
    /// "2h ago" — `RelativeDateTimeFormatter` with `.abbreviated` units.
    case relative
    /// "2026-05-09 14:32" — locale-aware short date + short time. Easier
    /// to copy/paste into bug reports or compare against external timelines.
    case absolute

    var id: String { rawValue }
    var label: String {
        switch self {
        case .relative: return "Relative (2h ago)"
        case .absolute: return "Absolute (2026-05-09 14:32)"
        }
    }

    func format(_ date: Date, reference: Date = .now) -> String {
        switch self {
        case .relative:
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: reference)
        case .absolute:
            return absoluteFormatter.string(from: date)
        }
    }

    /// `2026-05-09 14:32` — ISO-like, locale-independent for stability.
    /// Stays a single shared instance because `DateFormatter` is expensive
    /// to construct and the format never changes.
    private var absoluteFormatter: DateFormatter {
        Self.absoluteFormatter
    }

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
