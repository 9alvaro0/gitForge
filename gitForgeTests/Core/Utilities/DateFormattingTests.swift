import Foundation
import Testing
@testable import gitForge

@Suite("Date formatting — time since an update")
struct DateFormattingTests {
    private static let reference = Date(timeIntervalSince1970: 1_790_000_000)

    /// What the system calls the present moment in the current language.
    private static var now: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter.localizedString(fromTimeInterval: 0)
    }

    @Test("Within the first minute it reads as now, never as a time to come or a count of seconds",
          arguments: [0.0, 0.4, 5, 59.9, -3])
    func firstMinute(secondsAgo: TimeInterval) {
        let date = Self.reference.addingTimeInterval(-secondsAgo)
        #expect(DateDisplayMode.elapsed(since: date, reference: Self.reference) == Self.now)
    }

    @Test("From a minute on it is the relative date the lists show")
    func later() {
        let ages: [TimeInterval] = [60, 25 * 60, 3 * 3600, 2 * 86_400]
        for secondsAgo in ages {
            let date = Self.reference.addingTimeInterval(-secondsAgo)
            #expect(DateDisplayMode.elapsed(since: date, reference: Self.reference)
                    == DateDisplayMode.relative.format(date, reference: Self.reference))
        }
    }
}
