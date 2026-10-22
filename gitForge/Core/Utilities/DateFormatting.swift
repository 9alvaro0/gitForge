import Foundation

/// User-facing presentation style for `Date` values across History, Pulls,
/// Branches, and Commit detail. Persisted via `AppPreferences.dateDisplayMode`.
nonisolated enum DateDisplayMode: String, CaseIterable, Identifiable, Sendable {
    /// "2h ago" — `RelativeDateTimeFormatter` with `.abbreviated` units.
    case relative
    /// "2026-05-09 14:32" — locale-aware short date + short time. Easier
    /// to copy/paste into bug reports or compare against external timelines.
    case absolute

    var id: String { rawValue }
    var label: String {
        switch self {
        case .relative: return String(localized: "Relative (2h ago)")
        case .absolute: return String(localized: "Absolute (2026-05-09 14:32)")
        }
    }

    func format(_ date: Date, reference: Date = .now) -> String {
        switch self {
        case .relative:
            return Self.relativeFormatter.localizedString(for: date, relativeTo: reference)
        case .absolute:
            return absoluteFormatter.string(from: date)
        }
    }

    /// How long ago something was last brought up to date ("Updated 5m ago"):
    /// `.relative`, except that the first minute reads as "now", where the
    /// numeric style would say "in 0s" or count the seconds.
    static func elapsed(since date: Date, reference: Date = .now) -> String {
        guard reference.timeIntervalSince(date) >= 60 else {
            return nowFormatter.localizedString(fromTimeInterval: 0)
        }
        return relative.format(date, reference: reference)
    }

    /// Says "now" for no time at all. Shared like `relativeFormatter`.
    nonisolated(unsafe) private static let nowFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.dateTimeStyle = .named
        return f
    }()

    /// `2026-05-09 14:32` — ISO-like, locale-independent for stability.
    /// Stays a single shared instance because `DateFormatter` is expensive
    /// to construct and the format never changes.
    private var absoluteFormatter: DateFormatter {
        Self.absoluteFormatter
    }

    /// Shared like `absoluteFormatter`: this runs for every visible History,
    /// Branches and PR row on every render, and building a formatter (ICU
    /// data, locale lookup) per call dominated the row cost.
    /// `nonisolated(unsafe)`: configured once here and never mutated after;
    /// Foundation formatters are thread-safe for formatting.
    nonisolated(unsafe) private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
