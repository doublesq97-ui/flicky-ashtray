import XCTest
@testable import FlickyAshtray

final class CountingDayPolicyTests: XCTestCase {
    func testShanghaiCustomBoundaryBuildsEachCountingDayIndependently() {
        let calendar = calendar(in: "Asia/Shanghai")
        let policy = CountingDayPolicy(dayStartHour: 8, calendar: calendar)

        let beforeBoundary = policy.range(containing: date("2026-07-14 02:00", calendar: calendar))
        let afterBoundary = policy.range(containing: date("2026-07-14 09:00", calendar: calendar))

        XCTAssertEqual(beforeBoundary.start, date("2026-07-13 08:00", calendar: calendar))
        XCTAssertEqual(beforeBoundary.end, date("2026-07-14 08:00", calendar: calendar))
        XCTAssertEqual(afterBoundary.start, beforeBoundary.end)
        XCTAssertEqual(afterBoundary.end, date("2026-07-15 08:00", calendar: calendar))
    }

    func testLosAngelesSpringGapAdvancesMissingBoundaryAndKeepsRangesAdjacent() {
        let calendar = calendar(in: "America/Los_Angeles")
        let policy = CountingDayPolicy(dayStartHour: 2, calendar: calendar)
        let springDay = policy.range(
            forCivilDayContaining: date("2026-03-08 12:00", calendar: calendar)
        )
        let previous = policy.range(offsetBy: -1, from: springDay)
        let next = policy.range(offsetBy: 1, from: springDay)

        XCTAssertEqual(springDay.start, date("2026-03-08 03:00", calendar: calendar))
        XCTAssertEqual(springDay.end, date("2026-03-09 02:00", calendar: calendar))
        XCTAssertEqual(springDay.duration, 23 * 60 * 60, accuracy: 0.001)
        XCTAssertEqual(previous.end, springDay.start)
        XCTAssertEqual(springDay.end, next.start)
    }

    func testLosAngelesFallRepeatAlwaysChoosesFirstOccurrence() {
        let calendar = calendar(in: "America/Los_Angeles")
        let repeatedOneAM = CountingDayPolicy(dayStartHour: 1, calendar: calendar)
            .range(forCivilDayContaining: date("2026-11-01 12:00", calendar: calendar))
        let unambiguousTwoAM = CountingDayPolicy(dayStartHour: 2, calendar: calendar)
            .range(forCivilDayContaining: date("2026-11-01 12:00", calendar: calendar))

        XCTAssertEqual(repeatedOneAM.start, isoDate("2026-11-01T08:00:00Z"))
        XCTAssertEqual(repeatedOneAM.end, isoDate("2026-11-02T09:00:00Z"))
        XCTAssertEqual(repeatedOneAM.duration, 25 * 60 * 60, accuracy: 0.001)
        XCTAssertEqual(unambiguousTwoAM.start, isoDate("2026-11-01T10:00:00Z"))
    }

    func testDSTTransitionsHaveNoOverlapAndEveryInstantBelongsToOneRange() {
        assertSingleMembership(
            timeZoneID: "America/Los_Angeles",
            dayStartHour: 2,
            civilNoon: "2026-03-08 12:00"
        )
        assertSingleMembership(
            timeZoneID: "America/Los_Angeles",
            dayStartHour: 1,
            civilNoon: "2026-11-01 12:00"
        )
        assertSingleMembership(
            timeZoneID: "Asia/Shanghai",
            dayStartHour: 8,
            civilNoon: "2026-07-14 12:00"
        )
    }

    private func assertSingleMembership(
        timeZoneID: String,
        dayStartHour: Int,
        civilNoon: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let calendar = calendar(in: timeZoneID)
        let policy = CountingDayPolicy(dayStartHour: dayStartHour, calendar: calendar)
        let center = policy.range(
            forCivilDayContaining: date(civilNoon, calendar: calendar)
        )
        let ranges = (-2...2).map { policy.range(offsetBy: $0, from: center) }

        for pair in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(pair.0.end, pair.1.start, file: file, line: line)
        }

        let samples = ranges.flatMap { range in
            [
                range.start,
                range.start.addingTimeInterval(30 * 60),
                range.end.addingTimeInterval(-0.001)
            ]
        }
        for sample in samples {
            XCTAssertEqual(
                ranges.filter { $0.contains(sample) }.count,
                1,
                "\(sample) should belong to exactly one counting day",
                file: file,
                line: line
            )
        }
    }

    private func calendar(in timeZoneID: String) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = TimeZone(identifier: timeZoneID)!
        return value
    }

    private func date(_ value: String, calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
