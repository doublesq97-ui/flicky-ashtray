import AppKit
import XCTest
@testable import FlickyAshtray

final class WeeklyReportTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    func testReportBuildsRecentAndPreviousSevenCountingDays() {
        var store = SmokeStore()
        store.settings.dailyLimit = 2
        store.settings.dayStartHour = 8
        store.records = [
            date("2026-07-02 09:00"), date("2026-07-02 10:00"),
            date("2026-07-03 09:00"), date("2026-07-03 10:00"), date("2026-07-03 11:00"),
            date("2026-07-05 09:00"),
            date("2026-07-08 09:00"), date("2026-07-09 02:00"),
            date("2026-07-13 23:54"), date("2026-07-14 09:12")
        ]

        let report = SmokingLogic.weeklyReport(
            store: store,
            now: date("2026-07-14 10:00"),
            calendar: calendar
        )

        XCTAssertEqual(report.days.count, 7)
        XCTAssertEqual(report.previousDays.count, 7)
        XCTAssertEqual(report.rangeStart, date("2026-07-08 08:00"))
        XCTAssertEqual(report.rangeEnd, date("2026-07-15 08:00"))
        XCTAssertEqual(report.previousRangeStart, date("2026-07-01 08:00"))
        XCTAssertEqual(report.previousRangeEnd, date("2026-07-08 08:00"))
        XCTAssertEqual(report.previousComparableCutoff, date("2026-07-07 10:00"))
        XCTAssertEqual(report.days.first?.cigaretteCount, 2)
        XCTAssertEqual(report.days.last?.cigaretteCount, 1)
        XCTAssertEqual(report.days.last?.isCurrentCountingDay, true)
        XCTAssertEqual(report.days.last?.isComplete, false)
        XCTAssertEqual(report.days.last?.isPartial, true)
        XCTAssertEqual(report.days.last?.observedThrough, date("2026-07-14 10:00"))
        XCTAssertEqual(report.previousDays.last?.isComplete, false)
        XCTAssertEqual(report.previousDays.last?.isPartial, true)
        XCTAssertEqual(report.previousDays.last?.observedThrough, date("2026-07-07 10:00"))
        XCTAssertEqual(report.totalCount, 4)
        XCTAssertEqual(report.previousTotalCount, 6)
        XCTAssertEqual(report.reductionFromPreviousPeriod, 2)
        XCTAssertEqual(report.completedDayCount, 6)
        XCTAssertEqual(report.withinLimitDays, 6)
        XCTAssertTrue(report.encouragement.contains("少了 2 根"))
    }

    func testLongestGapUsesRawTimestampsAcrossMidnight() {
        var store = SmokeStore()
        store.records = [date("2026-07-13 23:54"), date("2026-07-14 09:12")]

        let report = SmokingLogic.weeklyReport(
            store: store,
            now: date("2026-07-14 10:00"),
            calendar: calendar
        )

        XCTAssertEqual(report.longestGapMinutes, 558)
        XCTAssertEqual(SmokingLogic.formattedGap(558), "9小时18分钟")
    }

    func testLongestGapMayBeginBeforeReportRangeWhenLaterRecordIsInside() {
        var store = SmokeStore()
        store.settings.dayStartHour = 8
        store.records = [date("2026-07-08 07:54"), date("2026-07-08 09:12")]

        let report = SmokingLogic.weeklyReport(
            store: store,
            now: date("2026-07-14 10:00"),
            calendar: calendar
        )

        XCTAssertEqual(report.rangeStart, date("2026-07-08 08:00"))
        XCTAssertEqual(report.longestGapMinutes, 78)
    }

    func testReportExcludesFutureRecordsAndUsesPositiveZeroCopy() {
        var store = SmokeStore()
        store.records = [date("2026-07-14 12:00")]

        let report = SmokingLogic.weeklyReport(
            store: store,
            now: date("2026-07-14 10:00"),
            calendar: calendar
        )

        XCTAssertEqual(report.totalCount, 0)
        XCTAssertNil(report.longestGapMinutes)
        XCTAssertEqual(report.encouragement, "这 7 天没有新增记录。安静的每一天，都在替你把习惯往回拉。")
    }

    func testComparisonUsesSameElapsedTimeInsteadOfAFullPreviousDay() {
        var store = SmokeStore()
        store.records = [
            date("2026-07-07 09:00"),
            date("2026-07-07 20:00"),
            date("2026-07-14 09:00")
        ]

        let report = SmokingLogic.weeklyReport(
            store: store,
            now: date("2026-07-14 10:00"),
            calendar: calendar
        )

        XCTAssertEqual(report.totalCount, 1)
        XCTAssertEqual(report.previousTotalCount, 1)
        XCTAssertEqual(report.reductionFromPreviousPeriod, 0)
        XCTAssertFalse(report.encouragement.contains("少了"))
    }

    func testDSTComparisonUsesEqualRelativeProgressAndMarksPreviousDayPartial() {
        let losAngeles = calendar(timeZoneID: "America/Los_Angeles")
        var store = SmokeStore()
        store.settings.dayStartHour = 2
        store.records = [
            date("2026-03-01 13:59", calendar: losAngeles),
            date("2026-03-01 14:01", calendar: losAngeles),
            date("2026-03-08 14:29", calendar: losAngeles)
        ]

        let report = SmokingLogic.weeklyReport(
            store: store,
            now: date("2026-03-08 14:30", calendar: losAngeles),
            calendar: losAngeles
        )

        XCTAssertEqual(report.days.last?.start, date("2026-03-08 03:00", calendar: losAngeles))
        XCTAssertEqual(report.previousComparableCutoff, date("2026-03-01 14:00", calendar: losAngeles))
        XCTAssertEqual(report.totalCount, 1)
        XCTAssertEqual(report.previousTotalCount, 1)
        XCTAssertEqual(report.previousDays.last?.cigaretteCount, 1)
        XCTAssertEqual(report.previousDays.last?.observedThrough, report.previousComparableCutoff)
        XCTAssertEqual(report.previousDays.last?.isPartial, true)
        XCTAssertEqual(report.previousDays.last?.isComplete, false)
    }

    func testFallDSTComparisonDoesNotTreatTheShorterPreviousDayAsComplete() {
        let losAngeles = calendar(timeZoneID: "America/Los_Angeles")
        var store = SmokeStore()
        store.settings.dayStartHour = 1
        store.records = [
            date("2026-10-25 12:59", calendar: losAngeles),
            date("2026-10-25 13:01", calendar: losAngeles),
            date("2026-11-01 12:29", calendar: losAngeles)
        ]

        let report = SmokingLogic.weeklyReport(
            store: store,
            now: date("2026-11-01 12:30", calendar: losAngeles),
            calendar: losAngeles
        )

        XCTAssertEqual(report.days.last?.start, ISO8601DateFormatter().date(from: "2026-11-01T08:00:00Z"))
        XCTAssertEqual(report.previousComparableCutoff, date("2026-10-25 13:00", calendar: losAngeles))
        XCTAssertEqual(report.totalCount, 1)
        XCTAssertEqual(report.previousTotalCount, 1)
        XCTAssertEqual(report.previousDays.last?.cigaretteCount, 1)
        XCTAssertEqual(report.previousDays.last?.isPartial, true)
        XCTAssertEqual(report.previousDays.last?.isComplete, false)
    }

    func testPNGRendererProducesRealPNGData() async throws {
        var store = SmokeStore()
        store.settings.dailyLimit = 8
        store.records = [date("2026-07-13 23:54"), date("2026-07-14 09:12")]
        let report = SmokingLogic.weeklyReport(
            store: store,
            now: date("2026-07-14 10:00"),
            calendar: calendar
        )

        let data = try await MainActor.run {
            try WeeklyReportExporter.pngData(
                for: report,
                appearance: NSAppearance(named: .aqua),
                scale: 1
            )
        }

        XCTAssertGreaterThan(data.count, 10_000)
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }

    func testExportThemeFollowsTheRequestedMacAppearance() {
        let lightAppearance = NSAppearance(named: .aqua)!
        let darkAppearance = NSAppearance(named: .darkAqua)!

        XCTAssertEqual(WeeklyReportExportTheme(appearance: lightAppearance), .light)
        XCTAssertEqual(WeeklyReportExportTheme(appearance: darkAppearance), .dark)
    }

    func testLightAndDarkExportsKeepTheSameCanvasAndUseDifferentColorways() async throws {
        var store = SmokeStore()
        store.settings.dailyLimit = 8
        store.records = [date("2026-07-13 23:54"), date("2026-07-14 09:12")]
        let report = SmokingLogic.weeklyReport(
            store: store,
            now: date("2026-07-14 10:00"),
            calendar: calendar
        )

        let (lightData, darkData, cardSize) = try await MainActor.run {
            (
                try WeeklyReportExporter.pngData(
                    for: report,
                    appearance: NSAppearance(named: .aqua),
                    scale: 1
                ),
                try WeeklyReportExporter.pngData(
                    for: report,
                    appearance: NSAppearance(named: .darkAqua),
                    scale: 1
                ),
                WeeklyReportExporter.cardSize
            )
        }

        let lightBitmap = try XCTUnwrap(NSBitmapImageRep(data: lightData))
        let darkBitmap = try XCTUnwrap(NSBitmapImageRep(data: darkData))
        let expectedWidth = Int(cardSize.width)
        let expectedHeight = Int(cardSize.height)

        XCTAssertEqual(lightBitmap.pixelsWide, expectedWidth)
        XCTAssertEqual(lightBitmap.pixelsHigh, expectedHeight)
        XCTAssertEqual(darkBitmap.pixelsWide, expectedWidth)
        XCTAssertEqual(darkBitmap.pixelsHigh, expectedHeight)
        XCTAssertNotEqual(lightData, darkData)
    }

    private func calendar(timeZoneID: String) -> Calendar {
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
}
